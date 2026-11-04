# frozen_string_literal: true

require "test_helper"

module Play
  class StandingsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @tournament.update_columns(seed: 99, swiss_rounds_count: 2, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      @tournament.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
    end

    test "a visitor sees the standings in the play layout" do
      get play_standings_path(@tournament.slug)

      assert_response :success
      assert_select "h2", text: "Standings"
      assert_select "tbody tr", 8
      assert_select "nav[data-play-nav] a[href=?][aria-current=page]", play_standings_path(@tournament.slug)
      assert_select "turbo-frame#modal", count: 0
    end

    test "the page follows the event's standings stream and refreshes by morph; the modal does not" do
      signed = Turbo::StreamsChannel.signed_stream_name(LiveBroadcasts.standings_stream(@tournament.id, :en))

      get play_standings_path(@tournament.slug)

      assert_select "turbo-cable-stream-source[signed-stream-name=?]", signed
      assert_select "meta[name='turbo-refresh-method'][content='morph']"

      get tournament_event_participants_path(@tournament), headers: { "Turbo-Frame" => "modal" }

      assert_select "turbo-cable-stream-source", count: 0
    end

    test "the old standings address redirects to the new one" do
      get tournament_event_participants_path(@tournament, locale: "pt")

      assert_response :found
      assert_redirected_to play_standings_path(@tournament.slug, locale: "pt")
    end

    test "the old standings address inside the modal frame stays a modal" do
      get tournament_event_participants_path(@tournament), headers: { "Turbo-Frame" => "modal" }

      assert_response :success
      assert_select "turbo-frame#modal"
    end

    test "a finished event shows final standings with the top cut positions first" do
      ranked = @tournament.event_participants.order(:created_at).to_a
      ranked.last.update!(final_position: 1)
      ranked.first.update!(final_position: 2)
      @tournament.update_column(:state, :finished) # rubocop:disable Rails/SkipsModelValidations

      get play_standings_path(@tournament.slug)

      assert_select "h2", text: "Final standings"
      assert_select "tbody tr" do |rows|
        assert_equal [ranked.last, ranked.first].map { |p| "event_participant_#{p.id}" }, rows.first(2).pluck("id")
      end
      assert_select "tbody tr:first-child [data-final-position]", text: "1"

      get play_standings_path(@tournament.slug, locale: "pt")
      assert_select "h2", text: "Classificação final"
    end
  end
end
