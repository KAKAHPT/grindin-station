# frozen_string_literal: true

require "test_helper"

module Results
  class ContestTest < ActiveSupport::TestCase
    setup do
      @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      @pod = @t.rounds.create!(type: SwissRound, number: 1).pods.first
      @seats = @pod.event_participants.to_a
    end

    test "contesting an applied result disputes the pod, calls a judge and tells the table" do
      Report.call(pod: @pod, participant: @seats[0], type: "Win", winner: @seats[0])

      assert_difference -> { Notification.where(kind: "result_contested").count }, 4 do
        Contest.call(pod: @pod, participant: @seats[1], reason: "Wrong winner")
      end

      @pod.reload
      assert_predicate @pod, :disputed?
      assert_equal :disputed, @pod.report_status
      call = JudgeCall.find_by!(pod: @pod)
      assert_equal "Result contested: Wrong winner", call.reason
      assert_equal @seats[1], call.participant
      assert(Notification.where(kind: "result_contested").all? { |n| n.subject == call })
      assert_equal 4, @pod.results.size
    end

    test "contesting a pending result disputes it" do
      @t.update!(result_confirmation: "all")
      Report.call(pod: @pod, participant: @seats[0], type: "Draw")

      Contest.call(pod: @pod, participant: @seats[2], reason: "Not a draw")

      assert_equal :disputed, @pod.reload.report_status
      assert_empty @pod.results
      call = JudgeCall.find_by!(pod: @pod)
      assert_equal(@pod.users.map(&:id).sort,
                   Notification.where(kind: "result_contested", subject: call).pluck(:user_id).sort)
    end

    test "a blank reason is refused" do
      Report.call(pod: @pod, participant: @seats[0], type: "Draw")

      error = assert_raises(NotAllowed) { Contest.call(pod: @pod, participant: @seats[1], reason: " ") }
      assert_equal "reason_required", error.message
      assert_not @pod.reload.disputed?
    end

    test "contesting with self-reporting disabled is refused" do
      Report.call(pod: @pod, participant: @seats[0], type: "Draw")
      @t.update!(self_report_enabled: false)

      error = assert_raises(NotAllowed) { Contest.call(pod: @pod, participant: @seats[1], reason: "x") }
      assert_equal "self_report_disabled", error.message
    end

    test "nothing to contest while playing, and only seated players may contest" do
      assert_raises(NotAllowed) { Contest.call(pod: @pod, participant: @seats[0], reason: "x") }

      Report.call(pod: @pod, participant: @seats[0], type: "Draw")
      outsider = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
        .event_participants.first
      assert_raises(NotAllowed) { Contest.call(pod: @pod, participant: outsider, reason: "x") }
      assert_not JudgeCall.exists?(pod: @pod)
    end

    test "clear_report_state! resets the reporting state" do
      @t.update!(result_confirmation: "one")
      Report.call(pod: @pod, participant: @seats[0], type: "Draw")
      Contest.call(pod: @pod, participant: @seats[1], reason: "x")

      @pod.reload.clear_report_state!

      @pod.reload
      assert_equal :playing, @pod.report_status
      assert_nil @pod.pending_result
      assert_empty @pod.confirmations
      assert_not @pod.disputed?
      assert_nil @pod.review_requested_at
    end
  end
end
