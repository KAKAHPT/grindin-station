# frozen_string_literal: true

require "test_helper"

module Organizer
  # Actions no other test opened: the circuits list and creation, and the organizer's league pages
  # (not linked from the navigation, reachable by URL).
  class UntestedActionsTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    end

    test "an organizer lists, opens the form for and creates a circuit" do
      get organizer_circuits_path
      assert_response :success

      get new_organizer_circuit_path
      assert_response :success
      assert_select "form[action=?]", organizer_circuits_path

      assert_difference -> { event_organizers(:standard_organizer).circuits.count }, 1 do
        post organizer_circuits_path, params: { circuit: { name: "Liga de Inverno", description: "Quatro etapas" } }
      end
      assert_redirected_to organizer_circuit_path(Circuit.find_by!(name: "Liga de Inverno"))
      follow_redirect!
      assert_response :success
    end

    test "an organizer lists leagues, creates one, opens it and deals a pickup pod" do
      get organizer_leagues_path
      assert_response :success

      get new_organizer_league_path
      assert_response :success

      assert_difference -> { League.count }, 1 do
        post organizer_leagues_path, params: {
          league: { name: "Liga das Quintas", start_time: 1.day.from_now, end_time: 30.days.from_now,
                    play_mode: "pickup" }
        }
      end
      league = League.find_by!(name: "Liga das Quintas")
      assert_redirected_to organizer_league_path(league)
      follow_redirect!
      assert_response :success

      get organizer_league_path(leagues(:standard_league))
      assert_response :success
    end

    test "a pickup league in play deals a pod from the organizer's page" do
      league = leagues(:standard_league)
      league.update_columns(state: League.states[:play], play_mode: League.play_modes[:pickup]) # rubocop:disable Rails/SkipsModelValidations

      post create_pickup_pod_organizer_league_path(league)

      assert_redirected_to organizer_league_path(league)
      assert_equal I18n.t("flash.notice.pickup_pod_created"), flash[:notice]
      follow_redirect!
      assert_response :success
    end

    test "a league without a name is refused with the form again" do
      assert_no_difference -> { League.count } do
        post organizer_leagues_path, params: { league: { name: "", start_time: 1.day.from_now } }
      end
      assert_response :unprocessable_entity
    end
  end
end
