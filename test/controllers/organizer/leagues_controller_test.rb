# frozen_string_literal: true

require "test_helper"

module Organizer
  class LeaguesControllerTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    end

    test "the league Settings show the country field and save it" do
      league = leagues(:standard_league)

      get edit_organizer_league_path(league)
      assert_select "input.uppercase[name='league[country]'][maxlength='2']"
      assert_select ".form-help", text: "Two-letter code, used by the country filter on /events"

      patch organizer_league_path(league), params: { league: { country: "es" } }
      assert_redirected_to organizer_league_path(league)
      assert_equal "ES", league.reload.country
    end
  end
end
