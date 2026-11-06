# frozen_string_literal: true

require "test_helper"

class OrganizersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Porto Grinders", email_address: "org-#{SecureRandom.hex(3)}@example.com",
                         password: "password123", handle: "porto-grinders-org")
    @organizer = EventOrganizer.create!(user: @user)
  end

  test "/organizers lists every organizer A–Z with their event count and next event, and filters by name and country" do # rubocop:disable Metrics/BlockLength
    @user.update!(country: "PT")
    soon = event("Next Cup", starts: 2.days.from_now)
    event("Done Cup", starts: 30.days.ago, state: :finished)
    event("Hidden Cup", starts: 3.days.from_now, state: :draft)
    other = User.create!(name: "Madrid Mana", email_address: "org2-#{SecureRandom.hex(3)}@example.com",
                         password: "password123", handle: "madrid-mana-org", country: "ES")
    EventOrganizer.create!(user: other)
    gone = User.create!(name: "Gone Org", email_address: "org3-#{SecureRandom.hex(3)}@example.com",
                        password: "password123", handle: "gone-org")
    EventOrganizer.create!(user: gone)
    gone.update_columns(anonymized_at: Time.current, handle: nil) # rubocop:disable Rails/SkipsModelValidations

    get organizers_path

    assert_response :success
    assert_select "[data-topbar] nav a[href=?]", organizers_path, text: "Organizers"
    assert_select "[data-organizer]", count: EventOrganizer.joins(:user).where(users: { anonymized_at: nil }).count
    assert_select "[data-organizer='gone-org']", count: 0
    assert_select "[data-organizer='porto-grinders-org'] a[href=?]", organizer_profile_path("porto-grinders-org"),
                  text: @user.name
    assert_select "[data-organizer='porto-grinders-org'] [data-organizer-events]", text: "2 events"
    assert_select "[data-organizer='porto-grinders-org'] [data-organizer-country]", text: "Portugal"
    assert_select "[data-organizer='porto-grinders-org'] [data-organizer-next] a[href=?]", play_event_path(soon.slug),
                  text: "Next Cup"
    assert_select "[data-organizer='madrid-mana-org'] [data-organizer-events]", text: "0 events"
    assert_select "[data-organizer='madrid-mana-org'] [data-organizer-next]", count: 0

    get organizers_path(q: "madrid")
    assert_select "[data-organizer]", count: 1
    assert_select "[data-organizer='madrid-mana-org']"

    get organizers_path(country: "PT")
    assert_select "[data-organizer='madrid-mana-org']", count: 0
    assert_select "[data-organizer='porto-grinders-org']"

    get organizers_path(q: "zzz")
    assert_select "[data-list-empty]"
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
    assert_select "[data-upcoming-event='#{soon.slug}'].lp-evr-lg", count: 0
    assert_select "[data-upcoming-event='#{soon.slug}']"
    assert_select "[data-upcoming-event='#{done.slug}']"
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
