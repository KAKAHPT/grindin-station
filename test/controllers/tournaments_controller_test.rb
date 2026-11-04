# frozen_string_literal: true

require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  test "the old page redirects to the event page" do
    tournament = events(:standard_tournament)

    get tournament_path(tournament)

    assert_redirected_to play_event_path(tournament.slug)
  end

  test "a draft or canceled tournament is not found for a visitor" do
    tournament = events(:standard_tournament)

    %i[draft canceled].each do |state|
      tournament.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
      get tournament_path(tournament)

      assert_response :not_found, state
    end
  end

  test "an unknown tournament is not found" do
    get tournament_path(SecureRandom.uuid)

    assert_response :not_found
  end
end
