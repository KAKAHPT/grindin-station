# frozen_string_literal: true

require "test_helper"

class OrganizerTournamentStructureTest < ActionDispatch::IntegrationTest
  setup do
    post session_path, params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
  end

  test "the form shows the suggestion and saves rounds, cut and round lengths" do
    tournament = TournamentBuilder.build(players: 24, organizer: event_organizers(:standard_organizer),
                                         state: :registration_open)

    get edit_organizer_tournament_path(tournament)
    assert_response :success
    assert_includes response.body, "Suggested for 24 players: 4 swiss rounds, top 10"
    assert_select "select[name='tournament[top_cut_size]'] option[value='13']", text: "Top 13"

    patch organizer_tournament_path(tournament), params: {
      tournament: { swiss_rounds_count: 5, top_cut_size: 13, round_minutes: 70, top_cut_round_minutes: 120 }
    }
    assert_redirected_to organizer_tournament_path(tournament)
    tournament.reload
    assert_equal [5, 13, 70, 120],
                 [tournament.swiss_rounds_count, tournament.top_cut_size, tournament.round_minutes,
                  tournament.top_cut_round_minutes]
  end

  test "structure fields are disabled once the swiss starts" do
    tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))

    get edit_organizer_tournament_path(tournament)
    assert_response :success
    %w[swiss_rounds_count top_cut_size round_minutes top_cut_round_minutes].each do |attribute|
      assert_select "[name='tournament[#{attribute}]'][disabled]"
    end
  end
end
