# frozen_string_literal: true

require "test_helper"

module Results
  class TimeoutTest < ActiveSupport::TestCase
    setup do
      @t = cut_tournament
      @pod = @t.rounds.find_by(number: 2).pods.first
    end

    test "highest seed advances: the top rank_score advances and the others are eliminated" do
      seated = @pod.event_participants.to_a
      best = seated.max_by(&:rank_score)

      Results::Timeout.call(pod: @pod, by: users(:organizer_user))

      current = Result.current.where(round: @pod.round, event_participant: seated).index_by(&:event_participant_id)
      assert_equal "Advance", current.fetch(best.id).type
      assert_equal %w[Eliminated], (seated - [best]).map { |p| current.fetch(p.id).type }.uniq
    end

    test "replay adds half the round time, requests review and records no result" do
      @t.update_columns(top_cut_timeout_rule: "replay", top_cut_round_minutes: 90) # rubocop:disable Rails/SkipsModelValidations

      assert_no_difference -> { Result.count } do
        Results::Timeout.call(pod: @pod, by: users(:organizer_user))
      end
      @pod.reload
      assert_equal 45, @pod.extra_time
      assert_not_nil @pod.review_requested_at
    end

    test "a Swiss pod is refused" do
      swiss = @t.rounds.find_by(number: 1).pods.first

      error = assert_raises(ArgumentError) { Results::Timeout.call(pod: swiss, by: users(:organizer_user)) }
      assert_equal "time called only applies to top-cut tables", error.message
    end

    test "a finished pod is refused" do
      Results::Timeout.call(pod: @pod, by: users(:organizer_user))

      error = assert_raises(Results::NotAllowed) { Results::Timeout.call(pod: @pod.reload, by: users(:organizer_user)) }
      assert_equal "already_finished", error.message
    end

    test "a second replay call adds no more time" do
      @t.update_columns(top_cut_timeout_rule: "replay", top_cut_round_minutes: 90) # rubocop:disable Rails/SkipsModelValidations
      Results::Timeout.call(pod: @pod, by: users(:organizer_user))

      error = assert_raises(Results::NotAllowed) { Results::Timeout.call(pod: @pod.reload, by: users(:organizer_user)) }
      assert_equal "time_already_called", error.message
      assert_equal 45, @pod.reload.extra_time
    end

    private

    def cut_tournament
      t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: (1..4).index_with(0))
      t.rounds.create!(type: SingleEliminationRound, number: 2)
      t
    end
  end
end
