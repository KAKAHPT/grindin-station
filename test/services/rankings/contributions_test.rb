# frozen_string_literal: true

require "test_helper"

module Rankings
  class ContributionsTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    setup do
      @organizer = event_organizers(:standard_organizer)
    end

    test "a played 16-player tournament: one row per participant with season, field, flags and points" do
      event = cut_event(16)
      winner = Seating.joins(pod: :round).find_by!(rounds: { event_id: event.id, type: "SingleEliminationRound" })
        .event_participant
      winner.update_columns(final_position: 1) # rubocop:disable Rails/SkipsModelValidations
      winner.player.user.update!(country: "PT", team: "Grinders")

      rows = Contributions.build(event.reload)

      assert_equal 16, rows.size
      row = rows.find { |r| r[:player_id] == winner.player_id }
      expected = Points.total(field: 16, wins: winner.number_of_wins, draws: winner.number_of_draws, byes: 0,
                              made_cut: true, top4: true, won: true)
      assert_equal({ event_id: event.id, season: event.start_time.year, field: 16, format: "multiplayer",
                     event_organizer_id: @organizer.id, country: "PT", team: "Grinders", made_cut: true,
                     top4: true, won: true, points: expected, invitational_points: 0 },
                   row.slice(:event_id, :season, :field, :format, :event_organizer_id, :country, :team, :made_cut,
                             :top4, :won, :points, :invitational_points))
      assert_equal(4, rows.count { |r| r[:made_cut] })
      rows.each do |r|
        assert_equal Points.total(field: 16, wins: r[:wins], draws: r[:draws], byes: r[:byes], made_cut: r[:made_cut],
                                  top4: r[:top4], won: r[:won]), r[:points]
      end
    end

    test "invitational points are points times the tier multiplier" do
      event = swiss_event(4, winners: { 1 => 0 })
      event.update_column(:tier, "silver") # rubocop:disable Rails/SkipsModelValidations

      row = Contributions.build(event.reload).find { |r| r[:wins] == 1 }

      assert_equal BigDecimal("3"), row[:points]
      assert_equal BigDecimal("4.5"), row[:invitational_points]
    end

    test "a Penalty counts as a loss: 0 points, losses 1" do
      event = swiss_event(4, winners: { 1 => 0 })
      loss = Loss.joins(:round).find_by!(rounds: { event_id: event.id })
      participant = loss.event_participant
      loss.destroy!
      Penalty.create!(round: loss.round, event_participant: participant)

      row = Contributions.build(event.reload).find { |r| r[:player_id] == participant.player_id }

      assert_equal [0, 1, 0, 0], row.values_at(:wins, :losses, :draws, :byes)
      assert_equal BigDecimal("0"), row[:points]
    end

    test "a bye (Advance in a swiss round) counts 1" do
      event = swiss_event(4, winners: { 1 => 0 })
      participant = event.event_participants.first
      Result.where(event_participant: participant).destroy_all
      Advance.create!(round: event.rounds.first, event_participant: participant)

      row = Contributions.build(event.reload).find { |r| r[:player_id] == participant.player_id }

      assert_equal 1, row[:byes]
      assert_equal BigDecimal("1"), row[:points]
    end

    test "a 1v1 match win counts as one win whatever the game score" do
      event = TournamentBuilder.build(players: 2, organizer: @organizer, state: :swiss, format: "one_v_one")
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(event, scores: { 1 => [2, 1] })

      rows = Contributions.build(event.reload)

      assert_equal [[0, 1, BigDecimal("0")], [1, 0, BigDecimal("3")]],
                   rows.map { |r| r.values_at(:wins, :losses, :points) }.sort
      assert_equal ["one_v_one"], rows.pluck(:format).uniq
    end

    test "a 1v1 cut match won (Win) gives no per-game points, only the bonuses" do
      event, cut_winner = one_v_one_cut_won_by_swiss_loser { |cut, id| TournamentBuilder.record_1v1!(cut, id, 2, 1) }

      assert_cut_winner_scores_bonuses_only(event, cut_winner)
    end

    test "a 1v1 cut match won (Advance, as Results::Apply records it) is not a bye" do
      event, cut_winner =
        one_v_one_cut_won_by_swiss_loser do |cut, id|
          Advance.create!(round: cut, event_participant_id: id, games_won: 2, games_lost: 1)
        end

      assert_cut_winner_scores_bonuses_only(event, cut_winner)
    end

    test "a tournament without a cut: the winner has won only, bonus 10" do
      event = swiss_event(8, winners: { 1 => 0, 2 => 0 })
      winner = Win.joins(:round).find_by!(rounds: { event_id: event.id }).event_participant
      winner.update_columns(final_position: 1) # rubocop:disable Rails/SkipsModelValidations

      row = Contributions.build(event.reload).find { |r| r[:player_id] == winner.player_id }

      assert_equal [false, false, true], row.values_at(:made_cut, :top4, :won)
      assert_equal BigDecimal("13"), row[:points]
    end

    test "a top-2 cut: positions 3 and 4 are not top 4" do
      event = one_v_one_cut_event(4, scores: { 1 => [2, 0], 2 => [2, 0] })
      cut = Seating.joins(pod: :round).where(rounds: { event_id: event.id, type: "SingleEliminationRound" })
        .pluck(:event_participant_id)
      ordered = cut + event.event_participants.where.not(id: cut).ids
      ordered.each_with_index { |id, i| EventParticipant.where(id: id).update_all(final_position: i + 1) } # rubocop:disable Rails/SkipsModelValidations

      rows = Contributions.build(event.reload).index_by { |r| r[:player_id] }
      flags = ordered.map { |id| rows.fetch(EventParticipant.find(id).player_id).values_at(:made_cut, :top4) }

      assert_equal [[true, true], [true, true], [false, false], [false, false]], flags
    end

    test "waitlisted and playerless participants are skipped; the field counts every non-waitlisted entry" do
      event = swiss_event(4, winners: { 1 => 0 })
      event.event_participants.first.update_column(:player_id, nil) # rubocop:disable Rails/SkipsModelValidations
      add_participant(event, "later").update_columns(waitlisted: true) # rubocop:disable Rails/SkipsModelValidations

      rows = Contributions.build(event.reload)

      assert_equal 3, rows.size
      assert_equal [4], rows.pluck(:field).uniq
    end

    test "a league gets games only: no cut flags or bonuses, whatever the final position" do
      league = league_with_wins(20, wins: 4)

      row = Contributions.build(league).find { |r| r[:wins] == 4 }

      assert_equal [false, false, false], row.values_at(:made_cut, :top4, :won)
      assert_equal 20, row[:field]
      assert_equal BigDecimal("15"), row[:points]
    end

    test "the number of queries does not grow with the field" do
      small_event = cut_event(4)
      large_event = cut_event(16)
      small = queries_of { Contributions.build(small_event) }
      large = queries_of { Contributions.build(large_event) }

      assert_equal small, large
    end

    private

    # A 2-player 1v1 with a final: the swiss loser wins the final (the block records their cut result) and
    # finishes first. Returns [event, cut winner].
    def one_v_one_cut_won_by_swiss_loser
      event = one_v_one_cut_event(2, scores: { 1 => [2, 0] })
      swiss = event.rounds.find_by!(number: 1)
      swiss_winner, cut_winner = [Win, Loss].map { |kind| kind.find_by!(round: swiss).event_participant }
      cut = event.rounds.find_by!(number: 2)
      Result.where(round: cut).destroy_all
      yield cut, cut_winner.id
      TournamentBuilder.record_1v1!(cut, swiss_winner.id, 1, 2)
      close_with_winner(cut, cut_winner)
      [event, cut_winner]
    end

    def close_with_winner(round, winner)
      round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
      winner.update_columns(final_position: 1) # rubocop:disable Rails/SkipsModelValidations
    end

    # A 1v1 tournament: one swiss round played with `scores`, then a top-2 cut round created.
    def one_v_one_cut_event(players, scores:)
      event = TournamentBuilder.build(players: players, organizer: @organizer, state: :swiss, format: "one_v_one")
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 2) # rubocop:disable Rails/SkipsModelValidations
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(event, scores: scores)
      event.rounds.create!(type: SingleEliminationRound, number: 2)
      event.reload
    end

    def assert_cut_winner_scores_bonuses_only(event, cut_winner)
      row = Contributions.build(event.reload).find { |r| r[:player_id] == cut_winner.player_id }

      assert_equal [0, 1, 0, 0], row.values_at(:wins, :losses, :draws, :byes)
      assert_equal [true, true, true], row.values_at(:made_cut, :top4, :won)
      assert_equal BigDecimal("20"), row[:points]
    end

    def swiss_event(players, winners:)
      event = TournamentBuilder.build(players: players, organizer: @organizer, state: :swiss)
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(event, winners: winners)
      event.reload
    end

    # One swiss round (pod 1 drawn, the others won by seat 0), then a top-4 cut round.
    def cut_event(players)
      event = TournamentBuilder.build(players: players, organizer: @organizer, state: :swiss)
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      event.rounds.create!(type: SwissRound, number: 1)
      winners = (1..(players / 4)).index_with { |pod| pod == 1 ? :draw : 0 }
      TournamentBuilder.play_round!(event, winners: winners)
      event.rounds.create!(type: SingleEliminationRound, number: 2)
      event.reload
    end

    # A league of `players`, the first of whom won `wins` closed play rounds and finished first.
    def league_with_wins(players, wins:)
      league = League.create!(name: "Liga", event_organizer: @organizer, state: :draft,
                              start_time: Time.current, end_time: 30.days.from_now)
      first = add_participant(league, "l0")
      (players - 1).times { |i| add_participant(league, "l#{i + 1}") }
      wins.times { |i| Win.create!(round: league_round(league, i + 1), event_participant: first) }
      first.update_columns(final_position: 1) # rubocop:disable Rails/SkipsModelValidations
      league.reload
    end

    def league_round(league, number)
      Round.create!(event: league, type: "SwissRound", number: number, is_play_round: true, finished_at: Time.current,
                    published: true)
    end

    def add_participant(event, name)
      event.event_participants.create!(player_name: name, player_email: "#{name}-#{SecureRandom.hex(3)}@example.com",
                                       accepted_terms: true)
    end

    # SQL statements run by the block, the query cache off so a repeated statement still counts.
    def queries_of(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      ActiveRecord::Base.uncached { ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block) }
      count
    end
  end
end
