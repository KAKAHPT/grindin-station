# frozen_string_literal: true

require "test_helper"

module Results
  # The top cut has no wins or draws: a win advances the winner and eliminates the table.
  class TopCutTest < ActiveSupport::TestCase
    setup do
      @t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      @t.update_columns(swiss_rounds_count: 1, top_cut_size: 16, result_confirmation: "none") # rubocop:disable Rails/SkipsModelValidations
      @t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => 0, 3 => 0, 4 => 0 })
      @t.update_column(:state, :single_elimination) # rubocop:disable Rails/SkipsModelValidations
      # Top 16: 4 pods, then a final
      @cut = @t.rounds.create!(type: SingleEliminationRound, number: 2, started_at: 1.hour.ago)
    end

    test "a win advances the winner and eliminates the table; the next cut round seats only the advanced" do
      winners =
        @cut.pods.order(:number).map do |pod|
          winner = pod.seatings.max_by(&:order).event_participant
          Apply.call(pod: pod, type: "Win", winner: winner)
          winner
        end

      @cut.pods.each do |pod|
        types = Result.current.where(round: @cut, event_participant_id: pod.seatings.map(&:event_participant_id))
        assert_equal({ "Advance" => 1, "Eliminated" => 3 }, types.group(:type).count)
      end
      @cut.update_columns(finished_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      final = @t.rounds.create!(type: SingleEliminationRound, number: 3)
      assert_equal winners.map(&:id).sort, final.seatings.map(&:event_participant_id).sort
    end

    test "a draw is refused" do
      pod = @cut.pods.first

      error = assert_raises(NotAllowed) { Apply.call(pod: pod, type: "Draw") }
      assert_equal "draw_in_top_cut", error.message
      assert_empty Result.current.where(round: @cut, type: %w[Draw Win Loss])
    end

    test "a self-reported win advances the winner once confirmed; a self-reported draw is refused" do
      pod = @cut.pods.first
      seats = pod.event_participants.to_a

      error = assert_raises(NotAllowed) { Report.call(pod: pod, participant: seats[0], type: "Draw") }
      assert_equal "draw_in_top_cut", error.message

      Report.call(pod: pod, participant: seats[0], type: "Win", winner: seats[2])
      assert_equal :pending, pod.reload.report_status
      Confirm.call(pod: pod, participant: seats[1])

      types = Result.current.where(round: @cut, event_participant_id: seats.map(&:id))
      assert_equal({ "Advance" => 1, "Eliminated" => 3 }, types.group(:type).count)
      assert_equal "Advance", Result.current.find_by(round: @cut, event_participant: seats[2]).type
    end

    test "with no confirmation required a cut table still waits for the opponent" do
      pod = @cut.pods.first
      seats = pod.event_participants.to_a

      Report.call(pod: pod, participant: seats[0], type: "Win", winner: seats[0])

      assert_equal :pending, pod.reload.report_status
      assert_empty Result.current.where(round: @cut, event_participant_id: seats.map(&:id))
      Confirm.call(pod: pod, participant: seats[1])
      assert_equal :completed, pod.reload.report_status
    end

    test "staff still apply a cut result alone" do
      pod = @cut.pods.first

      Apply.call(pod: pod, type: "Win", winner: pod.event_participants.first)

      assert_predicate pod.reload, :finished?
    end
  end
end
