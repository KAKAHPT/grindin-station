# frozen_string_literal: true

require "test_helper"

module Results
  class ConfirmTest < ActiveSupport::TestCase
    def pod_of(players, confirmation)
      t = TournamentBuilder.build(players: players, organizer: event_organizers(:standard_organizer))
      t.update!(result_confirmation: confirmation)
      pod = t.rounds.create!(type: SwissRound, number: 1).pods.first
      [pod, pod.event_participants.to_a]
    end

    test "one applies at the second confirmation and keeps the audit trail" do
      pod, seats = pod_of(4, "one")
      Report.call(pod: pod, participant: seats[0], type: "Win", winner: seats[0])

      Confirm.call(pod: pod, participant: seats[1])

      pod.reload
      assert_equal :completed, pod.report_status
      assert_nil pod.pending_result
      assert_equal [seats[0].id, seats[1].id].sort, pod.confirmations.keys.sort
      assert_equal seats[0].id, pod.reported_by_participant_id
      assert_equal %w[Win], Result.current.where(event_participant: seats[0]).pluck(:type)
    end

    test "all needs every seat of a pod of 4" do
      pod, seats = pod_of(4, "all")
      Report.call(pod: pod, participant: seats[0], type: "Draw")

      Confirm.call(pod: pod, participant: seats[1])
      Confirm.call(pod: pod, participant: seats[2])
      assert_equal :pending, pod.reload.report_status
      assert_empty pod.results

      Confirm.call(pod: pod, participant: seats[3])
      assert_equal :completed, pod.reload.report_status
      assert_equal %w[Draw] * 4, pod.results.map(&:type)
    end

    test "all needs three confirmations at a pod of 3" do
      pod, seats = pod_of(3, "all")
      assert_equal 3, pod.size
      Report.call(pod: pod, participant: seats[0], type: "Draw")

      Confirm.call(pod: pod, participant: seats[1])
      assert_equal :pending, pod.reload.report_status

      Confirm.call(pod: pod, participant: seats[2])
      assert_equal :completed, pod.reload.report_status
    end

    test "a player cannot confirm twice, nor without a pending result, nor from outside the pod" do
      pod, seats = pod_of(4, "all")
      assert_raises(NotAllowed) { Confirm.call(pod: pod, participant: seats[0]) }

      Report.call(pod: pod, participant: seats[0], type: "Draw")
      error = assert_raises(NotAllowed) { Confirm.call(pod: pod, participant: seats[0]) }
      assert_equal "already_confirmed", error.message

      outsider, = pod_of(4, "all").last
      assert_raises(NotAllowed) { Confirm.call(pod: pod, participant: outsider) }
      assert_equal 1, pod.reload.confirmations.size
    end

    test "a confirmation after the result applied is refused and nothing is applied twice" do
      pod, seats = pod_of(4, "one")
      Report.call(pod: pod, participant: seats[0], type: "Draw")
      Confirm.call(pod: pod, participant: seats[1])

      assert_raises(NotAllowed) { Confirm.call(pod: pod, participant: seats[2]) }
      assert_equal 4, Result.where(round: pod.round).count
    end
  end
end
