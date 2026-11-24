# frozen_string_literal: true

require "test_helper"

module Play
  # The TV screen (/t/:slug/screen): public, live, clock + results + tables.
  class ScreenTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    end

    test "before any round is published it waits, with no tables" do
      get play_screen_path(@tournament.slug)

      assert_response :success
      assert_select "[data-screen-clock]", text: /Waiting for the next round/
      assert_select "article[data-pairing-table]", 0
      assert_select "turbo-cable-stream-source"
      assert_select "meta[name='turbo-refresh-method'][content=morph]"
    end

    test "a running round shows the clock, every table and no result yet; a closed one says so" do
      round = @tournament.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true, started_at: 5.minutes.ago)

      get play_screen_path(@tournament.slug)
      assert_select "[data-screen-clock] [data-controller=big-timer]"
      assert_select "[data-screen-round]", text: /Round 1/
      assert_select "article[data-pairing-table]", 2
      assert_select "[data-screen-latest]", 0
      assert_select "[data-screen-pager]", 0

      TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
      get play_screen_path(@tournament.slug)
      assert_select "[data-screen-clock]", text: /Round closed/
      assert_select "[data-screen-progress]", text: %r{2\s*/ 2 tables finished}
    end

    test "a draft event has no screen for visitors" do
      @tournament.update_columns(state: Tournament.states[:draft]) # rubocop:disable Rails/SkipsModelValidations

      get play_screen_path(@tournament.slug)
      assert_response :not_found
    end
  end
end
