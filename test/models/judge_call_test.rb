# frozen_string_literal: true

require "test_helper"

class JudgeCallTest < ActiveSupport::TestCase
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @judge = users(:organizer_user)
  end

  test "goes open, acknowledged, closed" do
    call = JudgeCall.create!(event: @tournament, reason: "Rules question")
    assert call.open?

    call.acknowledge!(by: @judge)
    assert call.acknowledged?
    assert_equal @judge, call.acknowledged_by
    assert_not_nil call.acknowledged_at

    call.close!(by: @judge)
    assert call.closed?
    assert_not_nil call.closed_at
  end

  test "can close straight from open and records who handled it" do
    call = JudgeCall.create!(event: @tournament, reason: "Slow play")
    call.close!(by: @judge)

    assert call.closed?
    assert_equal @judge, call.acknowledged_by
  end

  test "a closed call cannot be acknowledged or closed again" do
    call = JudgeCall.create!(event: @tournament, reason: "x")
    call.close!(by: @judge)

    assert_raises(ActiveRecord::RecordInvalid) { call.acknowledge!(by: @judge) }
    assert_raises(ActiveRecord::RecordInvalid) { call.close!(by: @judge) }
  end

  test "an acknowledged call cannot be acknowledged again" do
    call = JudgeCall.create!(event: @tournament, reason: "x")
    call.acknowledge!(by: @judge)

    assert_raises(ActiveRecord::RecordInvalid) { call.acknowledge!(by: users(:player_one)) }
    assert_equal @judge, call.reload.acknowledged_by
  end

  test "the reason is 500 characters at most" do
    assert_not JudgeCall.new(event: @tournament, reason: "x" * 501).valid?
    assert JudgeCall.new(event: @tournament, reason: "x" * 500).valid?
  end

  test "a pod has one open call at most; opening another returns it without telling the staff again" do
    pod = @tournament.rounds.create!(type: SwissRound, number: 1).pods.first
    first = JudgeCalls::Open.call(event: @tournament, pod: pod, reason: "First")

    assert_no_difference -> { Notification.count } do
      assert_equal first, JudgeCalls::Open.call(event: @tournament, pod: pod, reason: "x" * 600)
    end
    assert_raises(ActiveRecord::RecordNotUnique) { JudgeCall.create!(event: @tournament, pod: pod, reason: "Race") }

    first.acknowledge!(by: @judge)
    assert_not_equal first, JudgeCalls::Open.call(event: @tournament, pod: pod, reason: "Again")
  end

  test "needs a reason and a known status" do
    assert_not JudgeCall.new(event: @tournament, reason: "").valid?
    assert_not JudgeCall.new(event: @tournament, reason: "x", status: "lost").valid?
  end

  test "open_or_acknowledged leaves closed calls out" do
    open = JudgeCall.create!(event: @tournament, reason: "a")
    acked = JudgeCall.create!(event: @tournament, reason: "b")
    acked.acknowledge!(by: @judge)
    closed = JudgeCall.create!(event: @tournament, reason: "c")
    closed.close!(by: @judge)

    assert_equal [open, acked].sort_by(&:id), JudgeCall.open_or_acknowledged.sort_by(&:id)
  end

  test "Open creates the call and notifies the staff" do
    pod = @tournament.rounds.create!(type: SwissRound, number: 1).pods.first
    participant = pod.event_participants.first

    call = nil
    assert_difference("Notification.count", 1) do
      call = JudgeCalls::Open.call(event: @tournament, pod: pod, participant: participant, reason: "Help")
    end

    assert call.persisted?
    assert call.open?
    assert pod.open_judge_call?
    assert_equal call, Notification.last.subject
    assert_equal "judge_call", Notification.last.kind
  end
end
