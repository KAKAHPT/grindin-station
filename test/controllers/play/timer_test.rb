# frozen_string_literal: true

require "test_helper"

module Play
  class TimerTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 3)
      @round.update!(published: true)
    end

    test "public page shows the clock data for a started round" do
      @round.update!(started_at: Time.zone.parse("2026-11-03 12:00:00"))

      get play_timer_path(@tournament.slug)

      assert_response :success
      assert_select "[data-big-timer-started-at-value]"
      assert_select "[data-big-timer-minutes-value='#{@tournament.round_minutes}']"
      assert_select "meta[http-equiv=refresh][content='30']"
      assert_includes response.body, "Round #3"
    end

    test "the clock has its time in the first response" do
      @round.update!(started_at: Time.current)

      get play_timer_path(@tournament.slug)

      assert_select "p.clock[data-controller=big-timer]" do |clock|
        assert_match(/\A\d{2}:\d{2}\z/, clock.text.strip)
      end
    end

    test "uses the top cut length for a single elimination round" do
      round = @tournament.rounds.create!(type: SingleEliminationRound, number: 4)
      round.update!(published: true, started_at: Time.current)

      get play_timer_path(@tournament.slug)

      assert_select "[data-big-timer-minutes-value='#{@tournament.top_cut_round_minutes}']"
    end

    test "waits when the current round has not started" do
      get play_timer_path(@tournament.slug)

      assert_response :success
      assert_includes response.body, "Waiting for the next round"
      assert_select "[data-big-timer-started-at-value]", false
    end

    test "waits when nothing is published" do
      @round.update!(published: false)

      get play_timer_path(@tournament.slug)

      assert_includes response.body, "Waiting for the next round"
    end

    test "says the round is closed once finished" do
      @round.update!(started_at: 1.hour.ago, finished_at: 5.minutes.ago)

      get play_timer_path(@tournament.slug)

      assert_includes response.body, "Round closed"
      assert_includes response.body, "Round #3"
      assert_select "[data-big-timer-started-at-value]", false
    end

    test "renders in portuguese" do
      get play_timer_path(@tournament.slug, locale: :pt)

      assert_includes response.body, "À espera da próxima ronda"
    end
  end
end
