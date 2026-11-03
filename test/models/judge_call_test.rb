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
