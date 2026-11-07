# frozen_string_literal: true

require "test_helper"

# Every page layout (public, play, organizer) opens with the same top bar: the rotating mark, the nav and the
# language switch.
class LayoutTest < ActionDispatch::IntegrationTest
  test "a public page has the top bar" do
    get profile_path(users(:player_one).handle)

    assert_response :success
    assert_top_bar
    assert_select "[data-topbar] a", text: "Sign in"
  end

  test "the Admin chip shows for admins only, on under /admin" do
    sign_in users(:organizer_user)
    get organizer_tournaments_path
    assert_select "[data-topbar] [data-admin-mode]", count: 0

    sign_in users(:admin_user)
    get admin_root_path
    assert_select "[data-topbar] [data-admin-mode].on", text: "Admin"
  end

  test "a play page has the top bar, the viewer and no event name in it" do
    tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    sign_in users(:player_one)

    get play_standings_path(tournament.slug)

    assert_response :success
    assert_top_bar
    assert_select "[data-topbar] [data-play-player]", text: users(:player_one).name
    assert_select "[data-topbar] [data-notifications-bell]"
    assert_select "[data-topbar]", text: /#{tournament.name}/, count: 0
    assert_select "[data-event-header] h1", text: "#{tournament.name} · Standings"
    assert_select ".evhead", count: 1
  end

  test "the organizer mode chip ignores host, protocol and script_name from the query string" do
    sign_in users(:organizer_user)

    get "/organizer/tournaments?host=evil.example&protocol=javascript&script_name=https://evil.example&anchor=x"

    assert_response :success
    href = css_select("[data-topbar] [data-organizer-mode]").first["href"]
    assert_equal "/tournaments", href
  end

  test "an organizer page has the top bar with the organizer mode chip and the account links" do
    sign_in users(:organizer_user)

    get organizer_tournaments_path

    assert_response :success
    assert_top_bar
    assert_select "[data-topbar] [data-organizer-mode]", text: "Organizer mode"
    assert_select "[data-topbar] a[href=?]", account_path, text: "Account"
    assert_select "[data-topbar] a", text: "Sign in", count: 0
    assert_select "#toggleSidebarMobile", count: 0
  end

  test "the language switch posts each locale and marks the current one" do
    get profile_path(users(:player_one).handle, locale: "pt")

    assert_select "[data-lang-switch] form[action=?][method=post]", locale_path, count: 3
    assert_select "[data-lang-switch] button.on[aria-pressed=true][data-locale=pt]", text: "PT"
    assert_select "[data-lang-switch] button.on", count: 1
    assert_select "[data-lang-switch] form:has(button[data-locale=es]) input[name=locale][value=es]"
  end

  test "the layouts link the mark as the favicon" do
    get root_path

    assert_select "link[rel=icon][type='image/svg+xml'][href*=mark]"
  end

  test "the mark ids are the same on every render, so a morph refresh keeps the gear turning" do
    tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    ids =
      Array.new(2) do
        get play_standings_path(tournament.slug)
        css_select(".gslogo [id]").map { |node| node["id"] }
      end

    assert_equal ids.first, ids.last
    assert_includes ids.first, "gsT-topbar"
    assert_includes ids.first, "gsT-evhead"
    assert_equal ids.first.uniq, ids.first
  end

  private

  def assert_top_bar # rubocop:disable Metrics/MethodLength -- one assertion per link
    assert_select "[data-topbar]", count: 1
    assert_select "[data-topbar] .gslogo[data-rotating]", count: 1
    assert_select "[data-topbar] nav a[href^=?]", events_path, text: "Events"
    assert_select "[data-topbar] nav a[href^=?]", rankings_path, text: "Rankings"
    assert_select "[data-topbar] nav a[href^=?]", circuits_path, text: "Circuits"
    assert_select "[data-topbar] nav a[href^=?]", organizers_path, text: "Organizers"
    assert_select "[data-topbar] nav a[href$=?]", "#about", count: 0
    assert_select "[data-topbar] [data-lang-switch] button", count: I18n.available_locales.size
    assert_select "[data-lang-switch] button[data-locale=en]", text: "EN"
    assert_select "[data-lang-switch] button[data-locale=pt]", text: "PT"
    assert_select "[data-lang-switch] button[data-locale=es]", text: "ES"
  end

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
