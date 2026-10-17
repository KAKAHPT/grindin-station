# frozen_string_literal: true

require "test_helper"

class EventParticipantsStandingsTest < ActionDispatch::IntegrationTest
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(seed: 99, swiss_rounds_count: 2, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    @tournament.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
  end

  test "public standings show the tiebreaker columns and explain them" do
    get tournament_event_participants_path(@tournament)

    assert_response :success
    assert_standings_headers
    assert_select "p", text: I18n.t("standings.help.beaten")
  end

  test "public standings render in portuguese" do
    get tournament_event_participants_path(@tournament, locale: "pt")

    assert_response :success
    assert_standings_headers
    assert_select "p", text: I18n.t("standings.help.beaten", locale: :pt)
  end

  private

  def assert_standings_headers
    %w[Pts OWR Beaten Unique Seats].each do |header|
      assert_select "th", text: /\A\s*#{header}\s*\z/
    end
  end
end
