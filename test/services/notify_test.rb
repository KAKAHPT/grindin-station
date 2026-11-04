# frozen_string_literal: true

require "test_helper"

class NotifyTest < ActiveSupport::TestCase
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @owner = @tournament.event_organizer.user
    @staff =
      %w[organizer judge scorekeeper].index_with do |role|
        user = User.create!(name: role, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
        EventStaff.create!(event: @tournament, user: user, role: role)
        user
      end
    @call = JudgeCall.create!(event: @tournament, reason: "Help")
  end

  test "staff gets one notification each: owner, organizer and judge, not the scorekeeper" do
    rows = Notify.staff(@tournament, kind: "judge_call", subject: @call)

    assert_equal [@owner, @staff["organizer"], @staff["judge"]].map(&:id).sort, rows.map(&:user_id).sort
    assert(rows.all? { |n| n.persisted? && n.kind == "judge_call" && n.subject == @call })
  end

  test "an owner who is also staff is notified once" do
    EventStaff.create!(event: @tournament, user: @owner, role: "judge")
    rows = Notify.staff(@tournament, kind: "judge_call", subject: @call)

    assert_equal(1, rows.count { |n| n.user_id == @owner.id })
    assert_equal 3, rows.size
  end

  test "participants of a pod are notified one each" do
    pod = @tournament.rounds.create!(type: SwissRound, number: 1).pods.first
    rows = Notify.participants(pod, kind: "round_published", subject: pod.round)

    assert_equal pod.users.map(&:id).sort, rows.map(&:user_id).sort
    assert_equal pod.event_participants.size, rows.size
  end
end
