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

    test "the league form offers only the organizer's own circuits" do
      mine = Circuit.create!(name: "My circuit", event_organizer: event_organizers(:standard_organizer))
      rival = User.create!(name: "Rival", email_address: "rival-#{SecureRandom.hex(3)}@example.com",
                           password: "password123")
      theirs = Circuit.create!(name: "Their circuit", event_organizer: EventOrganizer.create!(user: rival))

      get edit_organizer_league_path(leagues(:standard_league))

      assert_select "select[name='league[circuit_id]'] option[value=?]", mine.id
      assert_select "select[name='league[circuit_id]'] option[value=?]", theirs.id, count: 0
    end
  end
end
