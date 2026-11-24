# frozen_string_literal: true

require "test_helper"

# An event ticket shows the organizer's picture when they have one, their initials otherwise.
class EventTicketOrganizerAvatarTest < ActionDispatch::IntegrationTest
  setup do
    @with = event_organizers(:standard_organizer)
    @with.user.avatar.attach(io: file_fixture("cover1.jpg").open, filename: "a.jpg", content_type: "image/jpeg")
    @pictured = upcoming(@with, "Pictured Open")
  end

  test "the picture replaces the initials on the organizer's tickets, in the grid and in the list" do
    get events_path(q: "Pictured")
    assert_response :success
    assert_select "[data-upcoming-event='#{@pictured.slug}'] .lp-evr-org img[data-organizer-avatar]"
    assert_select "[data-upcoming-event='#{@pictured.slug}'] .lp-evr-org i", count: 0

    get events_path(q: "Pictured", view: "list")
    assert_select ".lp-evr-org img[data-organizer-avatar]"
  end

  test "an organizer without a picture keeps the initials; several pictured organizers load in one go" do
    other_user = User.create!(name: "Second Store", email_address: "second-store@example.com", password: "password123",
                              organizer: true)
    other_user.avatar.attach(io: file_fixture("cover2.jpg").open, filename: "b.jpg", content_type: "image/jpeg")
    other = upcoming(other_user.event_organizer, "Pictured Second")
    @with.user.avatar.purge

    get events_path(q: "Pictured")
    assert_select "[data-upcoming-event='#{@pictured.slug}'] .lp-evr-org i"
    assert_select "[data-upcoming-event='#{other.slug}'] .lp-evr-org img[data-organizer-avatar]"

    get root_path
    assert_response :success
  end

  private

  def upcoming(organizer, name)
    TournamentBuilder.build(players: 4, organizer: organizer, state: :registration_open).tap do |tournament|
      tournament.update!(name: name, start_time: 1.day.from_now, end_time: 2.days.from_now)
    end
  end
end
