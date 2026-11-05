# frozen_string_literal: true

require "test_helper"

class OrganizersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Porto Grinders", email_address: "org-#{SecureRandom.hex(3)}@example.com",
                         password: "password123", handle: "porto-grinders-org")
    @organizer = EventOrganizer.create!(user: @user)
  end

  test "an organizer page lists their public events, current first then past" do
    soon = event("Next Cup", starts: 2.days.from_now)
    done = event("Done Cup", starts: 30.days.ago, state: :finished)
    event("Hidden Cup", starts: 3.days.from_now, state: :draft)

    get organizer_profile_path("porto-grinders-org")

    assert_response :success
    assert_select "[data-organizer-header] h1", text: @user.name
    assert_select "[data-organizer-count]", text: "2 events"
    assert_select "[data-ticket-grid]", count: 2
    assert_select "[data-ticket-grid]:first-of-type [data-upcoming-event='#{soon.slug}'] .lp-evr-lg", count: 0
    assert_select "[data-upcoming-event='#{soon.slug}'].lp-evr-lg"
    assert_select "[data-upcoming-event='#{done.slug}'].lp-evr-lg"
    assert_select "[data-upcoming-event='hidden-cup']", count: 0
  end

  test "the ticket's organizer name and the About card link to the organizer page" do
    soon = event("Link Cup", starts: 2.days.from_now)

    get events_path
    organizer_href = organizer_profile_path("porto-grinders-org")
    assert_select "[data-upcoming-event='#{soon.slug}'] .lp-evr-org a[href=?]", organizer_href, text: @user.name

    get play_event_path(soon.slug)
    assert_select "[data-event-organizer] a[href=?]", organizer_href, text: @user.name
  end

  test "an organizer without events shows the empty card" do
    get organizer_profile_path("porto-grinders-org")

    assert_response :success
    assert_select "[data-list-empty]"
    assert_select "[data-organizer-count]", text: "0 events"
  end

  test "a player who is not an organizer, an unknown handle and an anonymised organizer answer 404" do
    player = User.create!(name: "Just Player", email_address: "just-#{SecureRandom.hex(3)}@example.com",
                          password: "password123", handle: "just-player")

    get organizer_profile_path(player.handle)
    assert_response :not_found

    get organizer_profile_path("nobody-here")
    assert_response :not_found

    @user.update_columns(anonymized_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    get organizer_profile_path("porto-grinders-org")
    assert_response :not_found
  end

  private

  def event(name, starts:, state: :registration_open)
    tournament = TournamentBuilder.build(players: 4, organizer: @organizer, state: state)
    tournament.update_columns(name: name, slug: name.parameterize, start_time: starts, end_time: starts + 8.hours) # rubocop:disable Rails/SkipsModelValidations
    tournament
  end
end
