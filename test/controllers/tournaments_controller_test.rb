# frozen_string_literal: true

require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  test "the old page redirects to the event page" do
    tournament = events(:standard_tournament)

    get tournament_path(tournament)

    assert_redirected_to play_event_path(tournament.slug)
  end

  test "an unknown tournament is not found" do
    get tournament_path(SecureRandom.uuid)

    assert_response :not_found
  end
end
