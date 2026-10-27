# frozen_string_literal: true

require "test_helper"

module Organizer
  class TournamentsControllerTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    end

    test "the new form has no structure suggestion before anyone registers" do
      get new_organizer_tournament_path
      assert_response :success
      assert_not_includes response.body, "Suggested for"
    end

    test "an invalid tournament re-renders the form with 422 instead of redirecting" do
      assert_no_difference -> { Tournament.count } do
        post organizer_tournaments_path, params: {
          tournament: { name: "Inválido", start_time: 1.day.from_now, end_time: 2.days.from_now, round_minutes: 0 }
        }
      end
      assert_response :unprocessable_entity
      assert_select "form[action='#{organizer_tournaments_path}']"
    end
  end
end
