# frozen_string_literal: true

require "test_helper"

module Organizer
  class LeagueDeskActionsTest < ActionDispatch::IntegrationTest
    setup do
      @organizer = event_organizers(:standard_organizer)
      post session_path, params: { session: { email_address: @organizer.user.email_address, password: "password123" } }
      @league = LeagueBuilder.build(players: 5, organizer: @organizer)
      @players = @league.event_participants.order(:created_at).to_a
    end

    test "the organizer cancels a full table from the desk, with a reason" do
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))
      table = @league.league_tables.find_by!(pod: pod)

      get organizer_league_path(@league)
      assert_select "[data-pending-table] [data-cancel-table] form[action=?]",
                    cancel_table_organizer_league_path(@league, table_id: table.id)
      patch cancel_table_organizer_league_path(@league, table_id: table.id), params: { reason: "" }
      assert_predicate table.reload, :filled?

      patch cancel_table_organizer_league_path(@league, table_id: table.id), params: { reason: "Ninguém apareceu" }

      assert_predicate table.reload, :cancelled?
      assert_equal 0, @league.rounds.count
    end

    test "the organizer takes a player out; one at a full table stays until it is finished" do
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))

      get organizer_league_path(@league, tab: "players")
      assert_select "[data-league-roster] [data-roster-player]", 5
      patch drop_participant_organizer_league_path(@league, participant_id: @players[0].id)
      assert_not @players[0].reload.dropped?
      assert_equal I18n.t("leagues.tables.not_allowed.finish_first"), flash[:alert]

      patch drop_participant_organizer_league_path(@league, participant_id: @players[4].id)
      assert_predicate @players[4].reload, :dropped?
      assert_not pod.reload.finished?
    end

    test "the organizer readmits a player who left, with the points they had" do
      player = @players[4]
      player.update!(league_score: 870)
      patch drop_participant_organizer_league_path(@league, participant_id: player.id)
      assert_predicate player.reload, :dropped?

      get organizer_league_path(@league, tab: "players")
      readmit = readmit_participant_organizer_league_path(@league, participant_id: player.id)
      assert_select "[data-roster-player='#{player.id}'] form[action='#{readmit}']"
      patch readmit

      assert_not player.reload.dropped?
      assert_nil player.dropped_at
      assert_equal 870, player.league_score
      assert_equal "participant_readmitted", AuditEvent.order(:created_at).last.action
    end

    test "a result needs a winner of the table or a draw" do
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))

      patch pod_result_organizer_league_path(@league, pod_id: pod.id), params: { result: @players[4].id }
      patch pod_result_organizer_league_path(@league, pod_id: pod.id), params: { result: "" }

      assert_not pod.reload.finished?
      assert_equal I18n.t("leagues.tables.not_allowed.invalid_result"), flash[:alert]
    end

    test "a league game is not rewritten once the league is finished" do
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))
      Results::Apply.call(pod: pod, type: "Win", winner: @players[0])
      scores = @players.map { |player| player.reload.league_score }
      @league.update_column(:state, League.states.fetch("finished")) # rubocop:disable Rails/SkipsModelValidations

      patch pod_result_organizer_league_path(@league, pod_id: pod.id), params: { result: @players[1].id }

      assert_equal(scores, @players.map { |player| player.reload.league_score })
    end

    test "extending the league is audited" do
      assert_difference -> { AuditEvent.for_action("league_end_changed").count }, 1 do
        patch organizer_league_path(@league), params: { league: { end_time: 2.months.from_now } }
      end
    end

    test "another organizer cannot touch the league" do
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))
      table = @league.league_tables.find_by!(pod: pod)
      delete session_path
      other = User.create!(name: "Outra Loja", email_address: "outra-loja@example.com", password: "password123",
                           confirmed_at: Time.current)
      EventOrganizer.create!(user: other)
      post session_path, params: { session: { email_address: other.email_address, password: "password123" } }

      patch cancel_table_organizer_league_path(@league, table_id: table.id), params: { reason: "x" }
      assert_response :not_found
      patch drop_participant_organizer_league_path(@league, participant_id: @players[4].id)
      assert_response :not_found
      patch transition_organizer_league_path(@league), params: { to: "closing" }
      assert_response :not_found
      patch pod_result_organizer_league_path(@league, pod_id: pod.id), params: { result: "draw" }
      assert_response :not_found

      assert_predicate table.reload, :filled?
      assert_predicate @league.reload, :play?
      assert_not @players[4].reload.dropped?
    end
  end
end
