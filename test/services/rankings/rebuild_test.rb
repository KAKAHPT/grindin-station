# frozen_string_literal: true

require "test_helper"

module Rankings
  class RebuildTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    setup do
      @organizer = event_organizers(:standard_organizer)
    end

    test "returns the counts and the time, and last_rebuilt_at is that time" do
      finished_event(4, winners: { 1 => 0 })

      outcome = Rebuild.call

      assert_equal RankingContribution.count, outcome[:contributions]
      assert_equal EloRating.count, outcome[:ratings]
      assert_in_delta outcome[:at], Rankings.last_rebuilt_at, 0.001
    end

    test "running twice gives identical rows" do
      finished_event(4, winners: { 1 => 0 })
      finished_event(4, winners: { 1 => :draw })

      Rebuild.call
      first = snapshot
      Rebuild.call

      assert_equal first, snapshot
    end

    test "a superseded result changes the player's points and rating on the next rebuild" do
      event = finished_event(4, winners: { 1 => 0 })
      pod = event.rounds.sole.pods.sole
      old_winner, new_winner = pod.seatings.order(:order).first(2).map { |s| s.event_participant.player_id }
      Rebuild.call
      before = EloRating.find_by!(player_id: old_winner, season: nil).rating

      Results::Apply.call(pod: pod, type: "Win", winner: pod.seatings.order(:order).second.event_participant,
                          by: @organizer.user)
      Rebuild.call

      points = [old_winner, new_winner].map { |id| RankingContribution.find_by!(player_id: id).points }
      # The correction on a finished tournament redoes the final positions: the new winner also takes the win bonus.
      assert_equal [BigDecimal("0"), BigDecimal("13")], points
      old = EloRating.find_by!(player_id: old_winner, season: nil)
      assert_operator before, :>, 1500
      assert_operator old.rating, :<, 1500
      assert_equal before, old.previous_rating
    end

    test "a finished event without results gives zero-point rows and no ratings" do
      event = TournamentBuilder.build(players: 4, organizer: @organizer, state: :finished)

      Rebuild.call

      rows = RankingContribution.where(event: event)
      assert_equal 4, rows.count
      assert_equal [BigDecimal("0")], rows.distinct.pluck(:points)
      assert_not EloRating.exists?(player_id: rows.select(:player_id))
    end

    test "ratings per season and for all time" do
      earlier = finished_event(4, winners: { 1 => 0 }, year: 2025)
      players = earlier.event_participants.map(&:player)
      later = finished_event(4, winners: { 1 => 0 }, year: 2026, players: players)

      Rebuild.call

      player = players.first
      ratings = EloRating.where(player: player).index_by(&:season)
      assert_equal [2025, 2026, nil].to_set, ratings.keys.to_set
      assert_equal [1, 1, 2], [ratings[2025], ratings[2026], ratings[nil]].map(&:games)
      assert_equal [2025, 2026].to_set, RankingContribution.where(player: player).pluck(:season).to_set
      assert later.persisted?
    end

    test "a player rated at Legacy and in pods has two independent ratings per season and all time" do
      pods = finished_event(4, winners: { 1 => 0 }, year: 2026)
      player = Win.find_by!(round: pods.rounds.sole).event_participant.player
      legacy = legacy_event(year: 2026)
      Win.find_by!(round: legacy.rounds.sole).event_participant.update_columns(player_id: player.id) # rubocop:disable Rails/SkipsModelValidations

      Rebuild.call

      ratings = EloRating.where(player: player).order(:play, :season).pluck(:play, :season, :rating, :games, :wins)
      assert_equal [["legacy", 2026, BigDecimal("1516"), 1, 1], ["legacy", nil, BigDecimal("1516"), 1, 1],
                    ["multiplayer", 2026, BigDecimal("1548"), 1, 1], ["multiplayer", nil, BigDecimal("1548"), 1, 1]],
                   ratings
      assert_equal %w[legacy multiplayer], RankingContribution.where(player: player).order(:format).pluck(:format)
    end

    test "a rating row of a pool no longer played is pruned" do
      legacy = legacy_event(year: 2026)
      Rebuild.call
      assert EloRating.exists?(play: "legacy")

      legacy.update_column(:game_format, "modern") # rubocop:disable Rails/SkipsModelValidations
      Rebuild.call

      assert_equal ["modern"], EloRating.distinct.pluck(:play)
    end

    test "an event no longer finished loses its contributions and ratings" do
      event = finished_event(4, winners: { 1 => 0 })
      Rebuild.call
      assert RankingContribution.exists?(event: event)

      event.update_column(:state, Tournament.states[:canceled]) # rubocop:disable Rails/SkipsModelValidations
      Rebuild.call

      players = event.event_participants.select(:player_id)
      assert_not RankingContribution.exists?(event: event)
      assert_not EloRating.exists?(player_id: players)
    end

    test "leagues count too" do
      league = finished_event(4, winners: { 1 => 0 })
      league.update_column(:type, "League") # rubocop:disable Rails/SkipsModelValidations

      Rebuild.call

      assert_equal 4, RankingContribution.where(event_id: league.id).count
    end

    private

    # A finished 4-player tournament (one swiss round played with `winners`), optionally in another year and
    # with the given players.
    def finished_event(count, winners:, year: nil, players: nil)
      event = TournamentBuilder.build(players: count, organizer: @organizer, state: :swiss)
      start = year ? Time.zone.local(year, 6, 1) : event.start_time
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 0, start_time: start, end_time: start + 1.day) # rubocop:disable Rails/SkipsModelValidations
      reuse_players(event, players) if players
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(event, winners: winners)
      event.update_column(:state, Tournament.states[:finished]) # rubocop:disable Rails/SkipsModelValidations
      event.reload
    end

    # A finished 2-player Legacy tournament: one swiss round won 2-0.
    def legacy_event(year:)
      event = TournamentBuilder.build(players: 2, organizer: @organizer, state: :swiss, format: "one_v_one")
      start = Time.zone.local(year, 6, 1)
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 0, start_time: start, end_time: start + 1.day, # rubocop:disable Rails/SkipsModelValidations
                           game_format: "legacy")
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(event, scores: { 1 => [2, 0] })
      event.update_column(:state, Tournament.states[:finished]) # rubocop:disable Rails/SkipsModelValidations
      event.reload
    end

    def reuse_players(event, players)
      players.zip(event.event_participants.order(:created_at)) do |player, entry|
        entry.update_columns(player_id: player.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def snapshot
      skip = %w[id created_at updated_at]
      [RankingContribution.order(:player_id, :event_id).map { |row| row.attributes.except(*skip) },
       EloRating.order(:player_id, :season).map { |row| row.attributes.except(*skip) }]
    end
  end
end
