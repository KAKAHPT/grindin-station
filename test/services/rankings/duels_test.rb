# frozen_string_literal: true

require "test_helper"

module Rankings
  class DuelsTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    setup do
      @organizer = event_organizers(:standard_organizer)
    end

    test "a won pod: the winner scores 1 against each, the others 0.5 among themselves" do
      pod = swiss_pod(winner: 1)
      w, a, b, c = player_ids(pod).values_at(1, 0, 2, 3)

      duels = Duels.for_pod(pod)

      assert_equal 6, duels.size
      [a, b, c].each { |loser| assert_equal 1, score_of(duels, w, loser) }
      [[a, b], [a, c], [b, c]].each { |x, y| assert_equal 0.5, score_of(duels, x, y) }
    end

    test "an all-Draw pod gives six duels of 0.5" do
      duels = Duels.for_pod(swiss_pod(winner: :draw))

      assert_equal [0.5] * 6, duels.map(&:last)
    end

    test "a Penalty is a loss" do
      pod = swiss_pod(winner: 0)
      loss = Loss.find_by!(event_participant_id: pod.seatings.second.event_participant_id)
      loss.destroy!
      Penalty.create!(round: loss.round, event_participant_id: loss.event_participant_id)
      winner, penalized = player_ids(pod).first(2)

      duels = Duels.for_pod(pod.reload)

      assert_equal 6, duels.size
      assert_equal 1, score_of(duels, winner, penalized)
    end

    test "a mixed pod: Draws beat the Loss and the Penalty, equal ranks draw" do
      pod = swiss_pod(winner: :draw)
      loss_seat, penalty_seat = pod.seatings.last(2)
      Result.where(event_participant_id: [loss_seat, penalty_seat].map(&:event_participant_id)).destroy_all
      Loss.create!(round: pod.round, event_participant_id: loss_seat.event_participant_id)
      Penalty.create!(round: pod.round, event_participant_id: penalty_seat.event_participant_id)
      draw_a, draw_b, loss, penalty = player_ids(pod)

      duels = Duels.for_pod(pod.reload)

      assert_equal 6, duels.size
      assert_equal 0.5, score_of(duels, draw_a, draw_b)
      [draw_a, draw_b].product([loss, penalty]).each { |x, y| assert_equal 1, score_of(duels, x, y) }
      assert_equal 0.5, score_of(duels, loss, penalty)
    end

    test "a player without a current result is skipped" do
      pod = swiss_pod(winner: 0)
      dropped = pod.seatings.last
      Result.where(event_participant_id: dropped.event_participant_id).destroy_all

      duels = Duels.for_pod(pod.reload)

      assert_equal 3, duels.size
      assert(duels.none? { |a, b, _| dropped.event_participant.player_id.in?([a, b]) })
    end

    test "an Advance (bye) is not a game" do
      pod = swiss_pod(winner: 0)
      seat = pod.seatings.last
      Result.where(event_participant_id: seat.event_participant_id).destroy_all
      Advance.create!(round: pod.round, event_participant_id: seat.event_participant_id)

      assert_equal 3, Duels.for_pod(pod.reload).size
    end

    test "a 1v1 pod is one duel scored by the match result" do
      event = TournamentBuilder.build(players: 2, organizer: @organizer, state: :swiss, format: "one_v_one")
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(event, scores: { 1 => [1, 2] })
      pod = event.rounds.first.pods.first
      first, second = player_ids(pod)

      assert_equal [[first, second, 0]], Duels.for_pod(pod)
    end

    test "a cut pod (Advance and Eliminated) is not rated" do
      event = swiss_event(4, winners: { 1 => 0 })
      event.update_columns(top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      cut = event.rounds.create!(type: SingleEliminationRound, number: 2)
      Result.where(round: cut).destroy_all
      pod = cut.pods.first
      pod.seatings.each_with_index do |seating, i|
        (i.zero? ? Advance : Eliminated).create!(round: cut, event_participant_id: seating.event_participant_id)
      end

      assert_equal 4, pod.seatings.size
      assert_empty Duels.for_pod(pod.reload)
    end

    test "a cut pod is not rated even with direct Win and Loss rows, and for_event leaves the cut out" do
      event = swiss_event(4, winners: { 1 => 0 })
      event.update_columns(top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      cut = event.rounds.create!(type: SingleEliminationRound, number: 2)
      Result.where(round: cut).destroy_all
      pod = cut.pods.first
      pod.seatings.each_with_index do |seating, i|
        (i.zero? ? Win : Loss).create!(round: cut, event_participant_id: seating.event_participant_id)
      end

      assert_empty Duels.for_pod(pod.reload)
      assert_equal [Duels.for_pod(event.rounds.find_by!(number: 1).pods.first)], Duels.for_event(event.reload)
    end

    test "for_event lists each pod's duels by round then pod number, in fixed queries" do
      event = swiss_event(8, winners: { 1 => 0, 2 => :draw })
      event.rounds.create!(type: SwissRound, number: 2)
      TournamentBuilder.play_round!(event, winners: { 1 => 2, 2 => 3 })
      expected = event.rounds.order(:number).flat_map { |round| round.pods.order(:number).map { Duels.for_pod(it) } }

      assert_equal expected, Duels.for_event(event.reload)
      assert_equal 4, expected.size

      small_event = swiss_event(4, winners: { 1 => 0 })
      small = queries_of { Duels.for_event(small_event) }
      large = queries_of { Duels.for_event(event) }

      assert_equal small, large
    end

    private

    def swiss_event(players, winners:)
      event = TournamentBuilder.build(players: players, organizer: @organizer, state: :swiss)
      event.update_columns(swiss_rounds_count: 2, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(event, winners: winners)
      event.reload
    end

    def swiss_pod(winner:)
      swiss_event(4, winners: { 1 => winner }).rounds.first.pods.first
    end

    def player_ids(pod) = pod.seatings.map { |seating| seating.event_participant.player_id }

    # Score of `first` in its duel with `second`, whichever way round the duel is listed.
    def score_of(duels, first, second)
      duel = duels.find { |x, y, _| [x, y].sort == [first, second].sort }
      duel.first == first ? duel.last : 1 - duel.last
    end

    def queries_of(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      ActiveRecord::Base.uncached { ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block) }
      count
    end
  end
end
