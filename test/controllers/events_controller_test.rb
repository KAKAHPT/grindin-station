# frozen_string_literal: true

require "test_helper"

# /events filters (spec M13 D12–D13): search, season, country, organizer and format as URL params over the lists.
class EventsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  setup do
    @organizer = event_organizers(:standard_organizer)
    other_user = User.create!(name: "Porto Org", handle: "porto-org", password: "password123",
                              email_address: "porto-org-#{SecureRandom.hex(3)}@example.com")
    @other = EventOrganizer.create!(user: other_user)
  end

  test "country=PT lists only the Portuguese events" do
    pt = upcoming("Lisbon Cup", country: "PT")
    es = upcoming("Madrid Cup", country: "ES")

    get events_path(country: "PT")

    assert_response :success
    assert_listed pt
    assert_not_listed es, events(:medium_tournament), leagues(:standard_league)
    assert_select "[data-filter-chips] [data-chip]", text: /Country\s+Portugal/
  end

  test "an unknown country is ignored and lists every event, the ones without a country too" do
    pt = upcoming("Lisbon Cup", country: "PT")

    get events_path(country: "XX")

    assert_listed pt, events(:medium_tournament), leagues(:standard_league)
    assert_select "[data-filter-chips]", count: 0
  end

  test "organizer=<handle> lists only that organizer's events; an unknown handle is ignored" do
    theirs = upcoming("Porto Org Cup", organizer: @other)
    ours = upcoming("Standard Cup")

    get events_path(organizer: "porto-org")
    assert_listed theirs
    assert_not_listed ours, leagues(:standard_league)
    assert_select "[data-chip]", text: /Organizer\s+Porto Org/

    get events_path(organizer: "nobody-here")
    assert_listed theirs, ours
  end

  test "season picks the year of the start among the past events" do
    old = upcoming("Old Cup", start: Time.zone.local(2025, 6, 1))
    recent = upcoming("Recent Cup", start: Time.zone.local(2026, 3, 1))

    get events_path(filter: "past", season: "2025")

    assert_listed old
    assert_not_listed recent
    assert_select "[data-filter-bar] .seg a.seg-on", text: "2025"
    assert_select "[data-filter-bar] .seg a", text: "All"
  end

  test "play=legacy lists only Legacy events, play=multiplayer only pods" do
    legacy = upcoming("Legacy Night", format: "one_v_one", game_format: "legacy")
    modern = upcoming("Modern Night", format: "one_v_one", game_format: "modern")
    pods = upcoming("Pod Night")

    get events_path(play: "legacy")

    assert_listed legacy
    assert_not_listed modern, pods
    assert_select "[data-chip]", text: /Format\s+Legacy/

    get events_path(play: "multiplayer")

    assert_listed pods
    assert_not_listed legacy, modern
  end

  test "an unknown play is ignored" do
    pods = upcoming("Pod Night")

    get events_path(play: "one_v_one")

    assert_listed pods
    assert_select "[data-filter-chips]", 0
  end

  test "a Legacy ticket names the game format and the match length" do
    duel = upcoming("Legacy Night", format: "one_v_one", game_format: "legacy")

    get events_path

    assert_select "[data-upcoming-event=?] .lp-evr-m", duel.slug, text: /Legacy · Bo3/
  end

  test "q matches the event name or the address" do
    by_name = upcoming("Porto Open")
    by_address = upcoming("Riverside Cup", address: "Rua das Flores, Porto")
    other = upcoming("Lisbon Cup", address: "Rua Augusta, Lisboa")

    get events_path(q: "porto")

    assert_listed by_name, by_address
    assert_not_listed other
  end

  test "the filters combine, the chips show each with a Clear all back to /events" do
    match = upcoming("Porto Duels", country: "PT", organizer: @other, format: "one_v_one", game_format: "other",
                                    start: Time.zone.local(2026, 12, 1))
    upcoming("Porto Pods", country: "PT", organizer: @other, start: Time.zone.local(2026, 12, 2))

    get events_path(country: "PT", organizer: "porto-org", season: "2026", play: "other", q: "porto")

    assert_listed match
    assert_select "[data-upcoming-event]", 1
    assert_select "[data-filter-chips] [data-chip]", 5
    assert_select "[data-filter-chips] a[data-clear-all][href=?]", events_path
    assert_select "a[href*='/events.']", 0 # play, not format: no /events.other links
    assert_select "[data-chip] a[href=?]",
                  events_path(organizer: "porto-org", season: "2026", play: "other", q: "porto")
  end

  test "the Upcoming / Past switch and the pagination keep the filters" do
    21.times { |index| upcoming("PT Cup #{index}", country: "PT", from_now: (index + 1).hours) }

    get events_path(country: "PT")

    assert_select "[data-list-filter] a[href=?]", events_path(filter: "past", country: "PT")
    assert_select "nav.pagination a[href*='page=2'][href*='country=PT']"
    assert_select "form[data-filter-bar] select[name=country] option[selected][value=PT]"
  end

  test "the option lists come from the visible events" do
    upcoming("Lisbon Cup", country: "PT", organizer: @other)
    hidden = upcoming("Hidden Cup", country: "ES")
    hidden.update_column(:state, Tournament.states[:draft]) # rubocop:disable Rails/SkipsModelValidations

    get events_path

    assert_select "select[name=country] option", 2 # All countries + PT
    assert_select "select[name=country] option[value=ES]", 0
    assert_select "select[name=organizer] option[value=porto-org]", text: "Porto Org"
    assert_select "select[name=play] option", 9 # All formats + the eight plays
    assert_select "select[name=play] option[value=legacy]", text: "Legacy"
    assert_select "select[name=play] option[value=multiplayer]", text: "cEDH · pods of four"
  end

  test "the featured strip lists the featured events above the filter bar, compact tickets below" do
    featured = upcoming("Spotlight Cup", featured: true)
    plain = upcoming("Plain Cup")

    get events_path

    assert_select "[data-featured-strip] h2", text: "Featured"
    assert_select "[data-featured-strip] [data-featured-event=?] a", featured.slug, text: "Spotlight Cup"
    assert_select "[data-featured-strip] [data-featured-event=?]", plain.slug, count: 0
    assert_operator response.body.index("data-featured-strip"), :<, response.body.index("data-filter-bar")
    assert_select ".lp-evr-lg", 0
    assert_select ".lp-evl-dense .lp-evr"
  end

  test "no featured strip when nothing is featured" do
    Event.update_all(featured: false) # rubocop:disable Rails/SkipsModelValidations

    get events_path

    assert_select "[data-featured-strip]", 0
  end

  test "view=list renders rows and is remembered in a cookie; an unknown view is the grid" do
    upcoming("Lisbon Cup", country: "PT")

    get events_path(view: "list")
    assert_select "[data-event-row]"
    assert_select ".lp-evr", 0
    assert_select "[data-view-switch] a[aria-pressed=true]", text: "List"
    assert_equal "list", cookies[:events_view]

    get events_path
    assert_select "[data-event-row]"

    get events_path(view: "weird")
    assert_select "[data-event-row]", 0
    assert_select ".lp-evr"
    assert_equal "list", cookies[:events_view]

    get events_path
    assert_select "[data-event-row]"
  end

  test "the view cookie is HttpOnly and SameSite=Lax" do
    get events_path(view: "list")

    cookie = Array(response.headers["Set-Cookie"]).join("\n").lines.find { |line| line.start_with?("events_view=") }
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
  end

  test "the view switch keeps the filters" do
    upcoming("Porto Cup", country: "PT")

    get events_path(country: "PT", q: "porto")

    assert_select "[data-view-switch] a[href=?]", events_path(country: "PT", q: "porto", view: "list"), text: "List"
    assert_select "[data-view-switch] a[href=?][aria-pressed=true]",
                  events_path(country: "PT", q: "porto", view: "grid"), text: "Grid"
  end

  private

  # A registration_open tournament of @organizer starting from_now (or at start); attributes: country, format, ...
  def upcoming(name, organizer: @organizer, from_now: 1.day, start: nil, **attributes)
    start ||= from_now.from_now
    event = Tournament.create!(name: name, event_organizer: organizer, state: :draft, start_time: start,
                               end_time: start + 1.day, **attributes)
    event.update_column(:state, Tournament.states[:registration_open]) # rubocop:disable Rails/SkipsModelValidations
    event
  end

  def assert_listed(*events)
    events.each { |event| assert_select "[data-upcoming-event=?]", event.slug, { count: 1 }, event.name }
  end

  def assert_not_listed(*events)
    events.each { |event| assert_select "[data-upcoming-event=?]", event.slug, { count: 0 }, event.name }
  end
end
