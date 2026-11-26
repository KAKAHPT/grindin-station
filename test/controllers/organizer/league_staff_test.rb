# frozen_string_literal: true

require "test_helper"

module Organizer
  # Staff on a league: the owner names them, and each role reaches what it may on the organizer's league page.
  class LeagueStaffTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      @organizer = event_organizers(:standard_organizer)
      @league = LeagueBuilder.build(players: 5, organizer: @organizer)
      @players = @league.event_participants.order(:created_at).to_a
      @helper = users(:player_one)
    end

    test "the owner adds and removes staff on the Staff tab" do
      sign_in @organizer.user

      get organizer_league_path(@league, tab: "staff")
      assert_select "[data-league-staff] form[action=?]", staff_organizer_league_path(@league)

      post staff_organizer_league_path(@league),
           params: { event_staff: { email_address: "nobody@example.com", role: "judge" } }
      assert_equal I18n.t("flash.alert.staff_user_not_found"), flash[:alert]

      assert_difference -> { @league.event_staff.count }, 1 do
        post staff_organizer_league_path(@league),
             params: { event_staff: { email_address: @helper.email_address, role: "judge" } }
      end
      assert_redirected_to organizer_league_path(@league, tab: "staff")
      staff = @league.event_staff.sole
      assert_equal "judge", staff.role

      get organizer_league_path(@league, tab: "staff")
      assert_select "[data-staff-row]", 1

      delete remove_staff_organizer_league_path(@league, staff_id: staff.id)
      assert_equal 0, @league.event_staff.count
    end

    test "someone who is not staff does not reach the league" do
      sign_in @helper

      get organizer_league_path(@league)

      assert_response :redirect
    end

    test "a scorekeeper enters results but neither runs the league, nor touches the roster, nor names staff" do
      staff_as "scorekeeper"
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))

      get organizer_leagues_path
      assert_select "a[href=?]", organizer_league_path(@league)
      get organizer_league_path(@league)
      assert_response :success
      assert_select "[data-result-draw]"
      assert_select "a", text: I18n.t("league_desk.tabs.edit"), count: 0
      assert_select "a", text: I18n.t("league_desk.tabs.staff"), count: 0

      patch pod_result_organizer_league_path(@league, pod_id: pod.id), params: { result: "draw" }
      assert_predicate pod.reload, :finished?

      patch drop_participant_organizer_league_path(@league, participant_id: @players[4].id)
      assert_not @players[4].reload.dropped?
      patch organizer_league_path(@league), params: { league: { name: "Taken over" } }
      assert_not_equal "Taken over", @league.reload.name
      assert_no_difference -> { EventStaff.count } do
        post staff_organizer_league_path(@league),
             params: { event_staff: { email_address: @helper.email_address, role: "organizer" } }
      end
    end

    test "a judge also takes a player out" do
      staff_as "judge"

      patch drop_participant_organizer_league_path(@league, participant_id: @players[4].id)

      assert_predicate @players[4].reload, :dropped?
    end

    test "a caster sees the league and changes nothing" do
      staff_as "caster"
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))

      get organizer_league_path(@league)
      assert_response :success
      assert_select "[data-result-draw]", 0
      assert_select "[data-cancel-table]", 0

      patch pod_result_organizer_league_path(@league, pod_id: pod.id), params: { result: "draw" }
      assert_not pod.reload.finished?
    end

    test "a staff organizer edits the league but does not name staff" do
      staff_as "organizer"

      get organizer_league_path(@league, tab: "edit")
      assert_response :success
      patch organizer_league_path(@league), params: { league: { name: "Renamed by staff" } }
      assert_equal "Renamed by staff", @league.reload.name

      get organizer_league_path(@league, tab: "staff")
      assert_select "[data-league-staff]", 0
    end

    test "the New league page shows the form beside a live preview of the public page" do
      sign_in @organizer.user

      get new_organizer_league_path
      assert_select "[data-controller='live-preview'] form[data-live-preview-target='form'] button[type=submit]", 0
      assert_select "[data-controller='live-preview'] iframe[data-live-preview-target='frame']"

      get preview_organizer_leagues_path, params: { league: { name: "Liga por criar" } }
      assert_response :success
      assert_select "h1", text: /Liga por criar/
      assert_equal 0, League.where(name: "Liga por criar").count
    end

    test "before the league starts the Tables tab says so, and the public count leaves out who left" do
      sign_in @organizer.user
      @league.update_columns(state: League.states[:registration_open]) # rubocop:disable Rails/SkipsModelValidations
      get organizer_league_path(@league)
      assert_select "[data-no-tables]", text: I18n.t("league_desk.no_tables_yet")

      @players.first.update_columns(dropped: true) # rubocop:disable Rails/SkipsModelValidations
      get league_path(@league)
      assert_match "4 registered", response.body
    end

    private

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end

    def staff_as(role)
      @league.event_staff.create!(user: @helper, role: role)
      sign_in @helper
    end
  end
end
