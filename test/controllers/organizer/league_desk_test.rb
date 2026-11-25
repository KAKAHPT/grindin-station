# frozen_string_literal: true

require "test_helper"

module Organizer
  class LeagueDeskTest < ActionDispatch::IntegrationTest
    setup do
      @organizer = event_organizers(:standard_organizer)
      post session_path, params: { session: { email_address: @organizer.user.email_address, password: "password123" } }
    end

    test "the form creates an open-tables league with its scoring settings" do
      get new_organizer_league_path
      assert_response :success
      assert_select "select[name='league[play_mode]'] option[selected][value=open_tables]"

      post organizer_leagues_path, params: { league: {
        name: "Liga de Dezembro", start_time: 1.day.from_now, end_time: 1.month.from_now, starting_points: 500,
        wager_percentage: 20, draw_rule: "lost", top_cut_size: 4, min_games_for_cut: 3, max_games_per_week: 7
      } }

      league = League.find_by!(name: "Liga de Dezembro")
      assert_redirected_to organizer_league_path(league)
      assert league.play_mode_open_tables?
      assert_equal [500, 20, "lost", 4, 3, 7],
                   [league.starting_points, league.wager_percentage.to_i, league.draw_rule, league.top_cut_size,
                    league.min_games_for_cut, league.max_games_per_week]
    end

    test "start, a cancellation approved, close, cut and the final finish the league" do # rubocop:disable Metrics/BlockLength
      league = LeagueBuilder.build(players: 8, organizer: @organizer, state: :registration_open, min_games_for_cut: 1)
      players = league.event_participants.order(:created_at).to_a

      get organizer_league_path(league)
      assert_select "[data-league-step=play]"
      patch transition_organizer_league_path(league), params: { to: "play" }
      assert_predicate league.reload, :play?

      played = LeagueBuilder.fill_table!(league, players.first(4))
      Results::Apply.call(pod: played, type: "Win", winner: players[0])
      stuck = LeagueBuilder.fill_table!(league, players.last(4)).league_table
      Leagues::Tables::RequestCancel.call(table: stuck, participant: players[4], reason: "Nobody could make it")

      patch update_path(league), params: { league: { starting_points: 5, state: "finished", name: "Renamed" } }
      assert_equal([1000, "play", "Renamed"], league.reload.then { |l| [l.starting_points, l.state, l.name] })

      patch transition_organizer_league_path(league), params: { to: "closing" }
      get organizer_league_path(league)
      assert_select "[data-league-desk=closing]"
      assert_select "[data-pending-table] [data-cancel-request]", text: /Nobody could make it/

      patch table_cancellation_organizer_league_path(league, table_id: stuck.id), params: { approve: "1" }
      assert_predicate league.reload, :closed?
      get organizer_league_path(league)
      assert_select "[data-cut-lead]", text: /4/
      assert_select "[data-league-step=finals]"

      patch transition_organizer_league_path(league), params: { to: "finals" }
      final = league.reload.rounds.find_by!(type: "LeagueCutRound")
      assert final.published? && final.started?
      patch transition_organizer_league_path(league), params: { to: "reopen" }
      assert_predicate league.reload, :finals?

      get organizer_league_path(league)
      assert_select "[data-cut-pod] [data-result-form]"
      assert_select "[data-close-cut-round]", 0
      patch pod_result_organizer_league_path(league, pod_id: final.pods.sole.id), params: { result: players[2].id }
      get organizer_league_path(league)
      assert_select "[data-close-cut-round]"
      patch close_cut_round_organizer_league_path(league, round_id: final.id)

      assert_predicate league.reload, :finished?
      assert_equal 1, players[2].reload.final_position
      get organizer_league_path(league)
      assert_select "[data-league-desk=finished]"
    end

    test "the organizer enters the result of a table that is stuck" do
      league = LeagueBuilder.build(players: 4, organizer: @organizer)
      players = league.event_participants.order(:created_at).to_a
      pod = LeagueBuilder.fill_table!(league, players)

      get organizer_league_path(league)
      assert_select "[data-pending-table] [data-result-form]"
      patch pod_result_organizer_league_path(league, pod_id: pod.id), params: { result: "draw" }

      assert_predicate pod.reload, :finished?
      assert_equal([1000] * 4, players.map { |player| player.reload.league_score.to_i })
      get organizer_league_path(league)
      assert_select "[data-pending-table]", 0
    end

    private

    def update_path(league) = organizer_league_path(league)
  end
end
