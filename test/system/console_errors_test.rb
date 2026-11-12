# frozen_string_literal: true

require "application_system_test_case"

# Every main page, opened in a real browser by a visitor, a player, the organizer and an admin: the console
# must log no error (a script that throws, a file that fails to load) and every data-controller on the page
# must be a Stimulus controller that exists, so no button is left without its behaviour.
class ConsoleErrorsTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: Time.current)
    @player = @round.pods.order(:number).first.seatings.order(:order).first.event_participant.player.user
    @player.update!(password: "password123")
    visit root_path
    console_errors # the browser keeps the log between tests: start from an empty one
  end

  test "a visitor's pages run clean" do
    assert_clean(public_pages)
  end

  test "a player's pages run clean" do
    sign_in_as(@player)

    assert_clean(public_pages.merge("my table" => play_me_path(@tournament.slug), "account" => account_path,
                                    "notifications" => notifications_path))
  end

  test "the organizer's and the admin's pages run clean" do
    organizer = users(:organizer_user)
    organizer.update_columns(admin: true) # rubocop:disable Rails/SkipsModelValidations
    sign_in_as(organizer)

    assert_clean(organizer_pages.merge(admin_pages))
  end

  private

  def public_pages
    lists.merge("event" => play_event_path(@tournament.slug), "pairings" => play_pairings_path(@tournament.slug),
                "standings" => play_standings_path(@tournament.slug), "timer" => play_timer_path(@tournament.slug),
                "profile" => profile_path(@player.handle))
  end

  def lists
    { "landing" => root_path, "fairness" => fairness_path, "events" => events_path, "rankings" => rankings_path,
      "rankings elo" => rankings_path(tab: "elo"), "rankings teams" => rankings_path(tab: "teams"),
      "circuits" => circuits_path, "organizers" => organizers_path, "feed" => feed_path,
      "sign in" => new_session_path, "sign up" => new_registration_path }
  end

  def organizer_pages
    { "my tournaments" => organizer_tournaments_path, "new tournament" => new_organizer_tournament_path,
      "overview" => organizer_tournament_path(@tournament), "settings" => edit_organizer_tournament_path(@tournament),
      "roster" => organizer_tournament_event_participants_path(@tournament, layout: "application"),
      "round" => organizer_tournament_round_path(@tournament, @round),
      "judge center" => organizer_tournament_judge_calls_path(@tournament),
      "staff" => organizer_tournament_staff_index_path(@tournament), "circuits" => organizer_circuits_path,
      "about" => edit_organizer_about_path }
  end

  def admin_pages
    { "admin" => admin_root_path, "admin audit" => admin_audit_path, "admin errors" => admin_errors_path,
      "admin events" => admin_events_path, "admin feed" => admin_feed_path,
      "admin organizers" => admin_organizers_path, "admin invitational" => admin_invitational_path }
  end

  def assert_clean(pages)
    assert_empty(pages.flat_map { |name, path| problems_on(name, path) })
  end

  def problems_on(name, path)
    visit path
    assert_selector "body"
    console_errors.map { |message| "#{name}: #{message.first(200)}" } +
      unknown_controllers.map { |controller| "#{name}: no Stimulus controller '#{controller}'" }
  end

  def console_errors
    page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" }.map(&:message)
  end

  # data-controller names on the page that Stimulus has no controller for (waits for the lazy ones to register).
  def unknown_controllers
    page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      const names = [...new Set([...document.querySelectorAll("[data-controller]")]
        .flatMap((el) => el.dataset.controller.trim().split(/\\s+/)))];
      const missing = () => names.filter((name) => !window.Stimulus?.router.modulesByIdentifier.has(name));
      const started = Date.now();
      (function check() { missing().length === 0 || Date.now() - started > 3000 ? done(missing()) : setTimeout(check, 100); })();
    JS
  end
end
