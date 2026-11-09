# frozen_string_literal: true

require "application_system_test_case"
require_relative "../support/rankings_fixture"

# M13 in the browser: /rankings tabs, the filter bar (selects submit on change), chips, the three "How…" dialogs;
# the /events country filter; approving a waiting-list signup on /admin/organizers.
class RankingsTest < ApplicationSystemTestCase
  include RankingsFixture

  test "the tabs switch the table" do
    build_rankings_world
    visit rankings_path
    assert_selector "tr[data-player]", count: 4

    click_link "Leaderboard"
    assert_selector "[data-rankings-tabs] a.on", text: "Leaderboard"
    assert_current_path(/tab=elo/)
    assert_selector "tr[data-player] [data-rating]", count: 4
    click_link "Teams"
    assert_selector "[data-rankings-tabs] a.on", text: "Teams"
    assert_selector "tr[data-team-row]", count: 2
    click_link "Ranking points"
    assert_selector "[data-rankings-tabs] a.on", text: "Ranking points"
  end

  test "a select narrows the table, a chip removes one filter and Clear all the rest" do
    build_rankings_world
    visit rankings_path
    assert_selector "tr[data-player]", count: 4

    find("select[name=country]").select("Portugal")
    assert_current_path(/country=PT/)
    assert_selector "tr[data-player]", count: 2
    assert_selector "[data-chip]", text: /Country\s+Portugal/

    find_field(name: "q").send_keys("carv", :enter)
    assert_current_path(/q=carv/)
    assert_selector "tr[data-player]", count: 1, text: "Ana Carvalho"
    assert_selector "[data-chip]", count: 2

    find("[data-chip] a[aria-label='Remove Search']").click
    assert_selector "[data-chip]", count: 1, text: /Country\s+Portugal/
    assert_selector "tr[data-player]", count: 2
    assert_no_current_path(/q=/)

    click_link "Clear all"
    assert_no_selector "[data-filter-chips]"
    assert_selector "tr[data-player]", count: 4
  end

  test "each How… dialog opens and closes with ✕ and with Escape" do
    build_rankings_world
    %w[points elo teams].each do |kind|
      visit rankings_path(tab: kind)
      dialog = "dialog[data-how=#{kind}][open]"

      click_button I18n.t("rankings.how.#{kind}.open"), match: :first
      within(dialog) { assert_text I18n.t("rankings.how.#{kind}.title") }
      find("#{dialog} button[aria-label=Close]").click
      assert_no_selector "dialog[open]"

      click_button I18n.t("rankings.how.#{kind}.open"), match: :first
      find("#{dialog} button[aria-label=Close]").send_keys(:escape)
      assert_no_selector "dialog[open]"
    end
  end

  test "/events: the country select narrows the tickets and shows the chip" do
    lisbon = upcoming_event("Lisbon Cup", "PT")
    madrid = upcoming_event("Madrid Cup", "ES")
    visit events_path
    assert_selector "[data-upcoming-event='#{madrid.slug}']"

    find("select[name=country]").select("Portugal")
    assert_current_path(/country=PT/)
    assert_selector "[data-upcoming-event='#{lisbon.slug}']"
    assert_no_selector "[data-upcoming-event='#{madrid.slug}']"
    assert_selector "[data-filter-chips] [data-chip]", text: /Country\s+Portugal/
  end

  test "an admin approves a waiting-list signup with an account and finds it under Approved" do
    user = users(:player_one)
    signup = WaitlistSignup.create!(name: "Player One", email: user.email_address)
    sign_in_as users(:admin_user)
    visit admin_organizers_path

    within("tr[data-signup='#{signup.id}']") { click_button "Approve" }
    assert_text I18n.t("admin.organizers.approved_notice", email: signup.email)
    assert_no_selector "tr[data-signup='#{signup.id}']"

    select "Approved", from: "Status"
    click_button "Filter"
    assert_current_path(/filter=approved/)
    assert_selector "tr[data-signup='#{signup.id}']", text: /Approved/
    assert_predicate user.reload.event_organizer, :present?
  end

  private

  def upcoming_event(name, country)
    start = 2.days.from_now
    event = Tournament.create!(name: name, event_organizer: event_organizers(:standard_organizer), state: :draft,
                               start_time: start, end_time: start + 1.day, country: country)
    event.update_column(:state, Tournament.states[:registration_open]) # rubocop:disable Rails/SkipsModelValidations
    event
  end
end
