# frozen_string_literal: true

require "application_system_test_case"

# The report-only policy must stay quiet on the pages used on an event day, so it can be enforced later.
class ContentSecurityPolicyTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: Time.current)
    @player = @round.pods.order(:number).first.seatings.order(:order).first.event_participant.player.user
    @player.update!(password: "password123")
  end

  test "the landing, play pages and organizer round page log no CSP violation" do
    visit root_path
    assert_selector "body"
    assert_no_csp_violations "landing"

    sign_in_as(@player)
    { "event" => play_event_path(@tournament.slug), "me" => play_me_path(@tournament.slug),
      "pairings" => play_pairings_path(@tournament.slug), "standings" => play_standings_path(@tournament.slug),
      "timer" => play_timer_path(@tournament.slug) }.each do |name, path|
      visit path
      assert_selector "body"
      assert_no_csp_violations name
    end

    Capybara.using_session(:organizer) do
      sign_in_as(users(:organizer_user))
      visit organizer_tournament_round_path(@tournament, @round)
      assert_text "Table 1"
      assert_no_csp_violations "organizer round"
    end
  end

  private

  def assert_no_csp_violations(page_name)
    messages = page.driver.browser.logs.get(:browser).map(&:message)
    violations = messages.grep(/Content Security Policy|Content-Security-Policy/i)
    assert_empty violations, "CSP violations on the #{page_name} page"
  end
end
