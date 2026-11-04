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

  test "a play page has the top bar, the viewer and no event name in it" do
    tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    sign_in users(:player_one)

    get play_standings_path(tournament.slug)

    assert_response :success
    assert_top_bar
    assert_select "[data-topbar] [data-play-player]", text: users(:player_one).name
    assert_select "[data-topbar] [data-notifications-bell]"
    assert_select "[data-topbar]", text: /#{tournament.name}/, count: 0
    assert_select "[data-event-header] h1", text: tournament.name
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

  test "the language switch keeps the page and marks the current locale" do
    get profile_path(users(:player_one).handle, locale: "pt")

    assert_select "[data-lang-switch] a.on[hreflang=pt]", text: "PT"
    assert_select "[data-lang-switch] a[href=?]", "#{profile_path(users(:player_one).handle)}?locale=en"
  end

  test "the layouts link the mark as the favicon" do
    get root_path

    assert_select "link[rel=icon][type='image/svg+xml'][href*=mark]"
  end

  private

  def assert_top_bar
    assert_select "[data-topbar]", count: 1
    assert_select "[data-topbar] .gslogo[data-rotating]", count: 1
    assert_select "[data-topbar] nav a[href^=?]", events_path, text: "Events"
    assert_select "[data-topbar] nav a[href^=?]", circuits_path, text: "Rankings"
    assert_select "[data-topbar] nav a[href$=?]", "#about", text: "About"
    assert_select "[data-topbar] [data-lang-switch] a", count: I18n.available_locales.size
    assert_select "[data-lang-switch] a[hreflang=en]", text: "EN"
    assert_select "[data-lang-switch] a[hreflang=pt]", text: "PT"
  end

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
