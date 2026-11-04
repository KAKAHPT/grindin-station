# frozen_string_literal: true

require "application_system_test_case"

# Two browsers: the player's table and the organizer's round page change as results come in, without a reload.
class LiveTableTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.update!(result_confirmation: "none", self_report_enabled: true)
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: Time.current)
    @pod, @other_pod = @round.pods.order(:number).first(2)
    @player = @pod.seatings.order(:order).first.event_participant
    clear_enqueued_jobs
  end

  test "the player sees the staff result, the organizer sees a player's report, neither reloads" do
    in_player_session do
      visit play_me_path(@tournament.slug)
      assert_selector "[data-report-status]", text: /playing/i
      mark_page
      assert_streams_connected
    end

    in_organizer_session do
      visit organizer_tournament_round_path(@tournament, @round)
      assert_streams_connected
      mark_winner(@pod, @player.name)
      mark_page
    end
    perform_enqueued_jobs

    in_player_session do
      assert_selector "[data-report-status]", text: /completed/i
      assert_no_link "Report result"
      assert_page_kept
    end

    reporter = @other_pod.seatings.order(:order).first.event_participant
    Results::Report.call(pod: @other_pod, participant: reporter, type: "Win", winner: reporter)
    perform_enqueued_jobs

    in_organizer_session do
      within("#pod_#{@other_pod.id}") { assert_text(/completed/i) }
      assert_page_kept
    end
  end

  test "a visitor's public pairings update by themselves and stay on the round they show" do
    @tournament.rounds.create!(type: SwissRound, number: 2).update!(published: true, started_at: Time.current)
    clear_enqueued_jobs

    Capybara.using_session(:visitor) do
      visit play_pairings_path(@tournament.slug, round: 1)
      assert_selector "[data-round-number='1']"
      assert_no_selector "[data-pod-number='#{@pod.number}'] li[data-winner]"
      mark_page
      assert_streams_connected
    end

    in_organizer_session do
      visit organizer_tournament_round_path(@tournament, @round)
      mark_winner(@pod, @player.name)
    end
    perform_enqueued_jobs
    perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) # the debounced pairings refresh

    Capybara.using_session(:visitor) do
      within("[data-pairings] [data-pod-number='#{@pod.number}']") do
        assert_selector "[data-pod-status]", text: /completed/i
        assert_selector "li[data-winner][data-participant-id='#{@player.id}']"
      end
      assert_selector "[data-round-number='1']"
      assert_page_kept
    end
  end

  private

  # A broadcast sent before the page's cable subscriptions are confirmed is lost; wait for every one of them.
  def assert_streams_connected
    assert_selector "turbo-cable-stream-source[connected]", visible: false
    assert_no_selector "turbo-cable-stream-source:not([connected])", visible: false
  end

  def in_player_session
    Capybara.using_session(:player) do
      unless @player_signed_in
        use_phone_viewport
        user = @player.player.user
        user.update!(password: "password123")
        sign_in_as(user)
        @player_signed_in = true
      end
      yield
    end
  end

  def in_organizer_session
    Capybara.using_session(:organizer) do
      sign_in_as(users(:organizer_user)) unless @organizer_signed_in
      @organizer_signed_in = true
      yield
    end
  end

  def mark_winner(pod, name)
    within("#pod_#{pod.id}") do
      find("li[role=button]") { |row| row["data-name"] == name }.click
      click_button "#{name} wins"
    end
    assert_text I18n.t("flash.notice.result_submitted")
  end

  # A full reload would drop this marker; a Turbo Stream replace or a morph refresh keeps it.
  def mark_page
    page.execute_script("window.liveMarker = true")
  end

  def assert_page_kept
    assert page.evaluate_script("window.liveMarker === true"), "the page was reloaded"
  end
end
