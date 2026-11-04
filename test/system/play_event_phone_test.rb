# frozen_string_literal: true

require "application_system_test_case"

# The public event page on a 375 px phone: one header card, no list of players, the player saves a decklist.
class PlayEventPhoneTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                          state: :registration_open)
    @me = @tournament.event_participants.order(:created_at).first
    @me.player.user.update!(password: "password123")
  end

  test "a player on a phone sees the header card once, no enrolled list, and saves their decklist" do
    # Headless Chrome will not shrink the window below 500 px; emulate the 375 px phone instead.
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: 375, height: 812, deviceScaleFactor: 2, mobile: true)
    sign_in_as(@me.player.user)

    visit play_event_path(@tournament.slug)

    assert_selector ".evhead", count: 1
    assert_selector "[data-event-header] h1", text: @tournament.name
    assert_no_selector "[data-play-header-nav]", visible: true
    assert_selector "nav[data-play-nav]", visible: true
    assert_no_selector "[data-enrolled], [data-waitlist]"
    others = @tournament.event_participants.where.not(id: @me.id).map(&:name)
    others.each { |name| assert_no_text name }

    within("[data-you]") do
      fill_in "Your decklist", with: "https://moxfield.com/decks/phone"
      click_button "Save"
    end

    assert_selector "[data-flash=notice]"
    assert_field "Your decklist", with: "https://moxfield.com/decks/phone"
    assert_equal "https://moxfield.com/decks/phone", @me.reload.decklist
    assert_equal 375, page.evaluate_script("window.innerWidth")
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 375
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
