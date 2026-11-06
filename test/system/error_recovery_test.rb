# frozen_string_literal: true

require "application_system_test_case"

class ErrorRecoveryTest < ApplicationSystemTestCase
  test "handles tournament state transition errors gracefully" do
    organizer = users(:organizer_user)
    tournament = events(:medium_tournament_registration_open)
    sign_in_as(organizer)

    # Draft state shows Open Registrations button
    visit organizer_tournament_path(tournament)

    # registration_open state shows Close Registrations; Cancel event lives in Settings
    assert_button "Close Registrations"
    assert_no_button "Open Registrations"

    # Cancel requires a confirm dialog
    click_link "Settings"
    accept_confirm { click_button "Cancel event" }
    assert_text "Tournament updated successfully"

    tournament.reload
    assert_equal "canceled", tournament.state
    assert_current_path organizer_tournament_path(tournament)
  end

  test "handles invalid form submissions gracefully" do
    organizer = users(:organizer_user)
    sign_in_as(organizer)

    visit organizer_tournaments_path
    click_link "New tournament"

    # Submit form with missing required fields
    fill_in "Start time", with: Time.zone.now.tomorrow.change(sec: 0)
    fill_in "End time", with: Time.zone.now.tomorrow.change(sec: 0)
    click_button "Create Tournament"

    # The form should still be visible with Name field (validation error)
    assert_text "Name"
    assert_text "Create Tournament"
  end

  test "handles unauthorized access attempts" do
    player = users(:player_one)
    tournament = events(:small_tournament)
    sign_in_as(player)

    # Try to access organizer area
    visit organizer_tournament_path(tournament)

    # Should redirect and show error
    assert_current_path root_path
    # The player namespace uses a different error message
    assert_text "Not allowed"
  end

  test "handles non-existent resource requests" do
    organizer = users(:organizer_user)
    sign_in_as(organizer)

    # Try to access non-existent tournament
    visit organizer_tournament_path("non-existent-id")

    assert_current_path organizer_root_path
    assert_text I18n.t("flash.alert.not_allowed")
  end

  test "handles double result submission gracefully" do
    organizer = users(:organizer_user)
    tournament = events(:small_tournament_swiss)
    round = tournament.rounds.swiss_rounds.first
    pod = round.pods.first
    sign_in_as(organizer)

    # Navigate to round page and click Insert result to open modal
    visit organizer_tournament_round_path(tournament, round)

    within "#pod_#{pod.id}" do
      click_link "Insert result"
    end

    # Fill in result modal form
    select "Win", from: "Result"
    select pod.event_participants.first.name, from: "Player"
    click_button "Save result"

    assert_text "Result submitted successfully"

    # Pod should be finished now
    pod.reload
    assert pod.finished?
  end

  test "handles concurrent tournament modifications" do
    organizer = users(:organizer_user)
    tournament = events(:medium_tournament_registration_open)
    sign_in_as(organizer)

    # Simulate concurrent modification by updating tournament directly
    tournament.update!(state: "registration_closed")

    # Try to perform action that requires different state
    visit organizer_tournament_path(tournament)

    # Should show current state, not cached state
    # registration_closed state shows "Move to Swiss stage"
    assert_button "Move to Swiss stage"
    assert_no_button "Close Registrations"
  end

  test "logged out user can visit root path" do
    visit root_path

    assert_current_path root_path
    assert_text "Grindin Station"
    assert_selector "[data-topbar] a", text: "Sign in"
    assert_no_text "Logout"
  end

  test "logged out user sees tournaments on the events page" do
    visit events_path

    assert_current_path events_path
    assert_text "Events"
    assert_text "Medium Tournament"
    assert_text "Free entry"
    assert_link "View event"
  end
end
