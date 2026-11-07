# frozen_string_literal: true

require "test_helper"

module Organizer
  class PreviewsControllerTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    end

    test "a tournament not created yet previews as the public page without saving anything" do
      assert_no_difference -> { Tournament.count } do
        get preview_organizer_tournaments_path,
            params: { tournament: { name: "Draft Night", game_format: "commander", address: "Rua das Flores 10, Porto",
                                    prizes: "Foil Mox" } }
      end

      assert_response :success
      assert_select "[data-event-header] h1", text: "Draft Night"
      assert_select "main", text: /Rua das Flores 10, Porto/
      assert_select "main", text: /Foil Mox/
    end

    test "editing previews the typed values and leaves the record untouched" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))

      get preview_organizer_tournament_path(tournament), params: { tournament: { name: "Renamed Cup" } }

      assert_response :success
      assert_select "[data-event-header] h1", text: "Renamed Cup"
      assert_not_equal "Renamed Cup", tournament.reload.name
    end

    test "another organizer's tournament is not previewable" do
      other = EventOrganizer.create!(user: users(:player_one))
      tournament = TournamentBuilder.build(players: 4, organizer: other)

      get preview_organizer_tournament_path(tournament), params: { tournament: { name: "x" } }

      assert_response :redirect
    end

    test "a visitor is sent to sign in" do
      delete session_path
      get preview_organizer_tournaments_path, params: { tournament: { name: "x" } }

      assert_redirected_to new_session_path
    end
  end
end
