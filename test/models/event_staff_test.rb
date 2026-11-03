# frozen_string_literal: true

require "test_helper"

class EventStaffTest < ActiveSupport::TestCase
  setup do
    @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                          state: :registration_open)
    @judge = User.create!(name: "Judge", email_address: "judge-#{SecureRandom.hex(3)}@example.com",
                          password: "password123")
  end

  test "staff_role_for is organizer for the owner, the row's role for staff and nil for others" do
    EventStaff.create!(event: @tournament, user: @judge, role: "judge")

    assert_equal "organizer", users(:organizer_user).staff_role_for(@tournament)
    assert_equal "judge", @judge.staff_role_for(@tournament)
    assert_nil users(:player_one).staff_role_for(@tournament)
  end

  test "a user has at most one role per event" do
    EventStaff.create!(event: @tournament, user: @judge, role: "judge")
    duplicate = EventStaff.new(event: @tournament, user: @judge, role: "scorekeeper")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:user_id, :taken)
  end

  test "the role must be one of the staff roles" do
    assert_not EventStaff.new(event: @tournament, user: @judge, role: "player").valid?
    assert_equal %w[organizer judge scorekeeper], EventStaff::ROLES
  end

  test "staffed_by covers owned and staffed events only" do
    other = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                    state: :registration_open)
    EventStaff.create!(event: @tournament, user: @judge, role: "judge")

    assert_equal [@tournament.id], Tournament.staffed_by(@judge).ids
    assert_includes Tournament.staffed_by(users(:organizer_user)).ids, other.id
    assert_empty Tournament.staffed_by(users(:player_one))
  end
end
