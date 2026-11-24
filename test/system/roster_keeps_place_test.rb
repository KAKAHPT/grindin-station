# frozen_string_literal: true

require "application_system_test_case"

# A row action on a long roster comes back to the same place, and its notice leaves on its own.
class RosterKeepsPlaceTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 40, organizer: event_organizers(:standard_organizer),
                                          state: :registration_open)
  end

  test "checking in a player at the bottom of the roster keeps the scroll, and the notice goes away" do
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_event_participants_path(@tournament, layout: "application")
    last_check_in = all("form[action$='/check_in'] button").last
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", last_check_in)
    before = page.evaluate_script("window.scrollY")
    assert_operator before, :>, 200

    last_check_in.click

    assert_selector "#flash-notice"
    assert_equal 39, all("form[action$='/check_in']").size
    assert_in_delta before, page.evaluate_script("window.scrollY"), 60
    assert_no_selector "#flash-notice", wait: 8
  end
end
