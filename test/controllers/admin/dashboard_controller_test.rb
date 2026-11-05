# frozen_string_literal: true

require "test_helper"

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "anonymous visitors get a 404" do
      get admin_root_path

      assert_response :not_found
    end

    test "a non-admin user gets a 404" do
      sign_in users(:organizer_user)

      get admin_root_path

      assert_response :not_found
    end

    test "an admin sees the dashboard" do
      sign_in users(:admin_user)

      get admin_root_path

      assert_response :success
      assert_select "section.card h2.card-title", text: "People"
      assert_select "nav.tabs a", text: "Overview"
    end

    test "the overview shows the health row of a running tournament with a late round" do
      tournament = TournamentBuilder.build(players: 12, organizer: event_organizers(:standard_organizer))
      round = tournament.rounds.create!(type: "SwissRound", number: 1)
      round.update_columns(started_at: 90.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      pods = round.pods.order(:number).to_a
      pods[0].update_columns(disputed: true) # rubocop:disable Rails/SkipsModelValidations
      pods[1].update_columns(pending_result: { "winner" => 1 }, review_requested_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      tournament.judge_calls.create!(reason: "Rules question", pod: pods[2])
      sign_in users(:admin_user)

      get admin_root_path

      assert_response :success
      assert_select "tr[data-health='#{tournament.id}']" do
        assert_select "a[href='#{organizer_tournament_path(tournament)}']", text: tournament.name
        assert_select "td[data-col=round]", text: "1"
        assert_select "td[data-col=judge_calls]", text: "1"
        assert_select "td[data-col=disputed]", text: "1"
        assert_select "td[data-col=pending]", text: "1"
        assert_select "td[data-col=review]", text: "1"
        assert_select "td[data-col=late]", text: /Late/
      end
    end

    test "the overview says nothing is running when no event is ongoing" do
      Event.where(state: [3, 4]).update_all(state: 5) # rubocop:disable Rails/SkipsModelValidations
      sign_in users(:admin_user)

      get admin_root_path

      assert_select "[data-health-empty]", text: "Nothing running"
      assert_select "tr[data-health]", count: 0
    end

    test "the overview shows the people, events, errors and recent audit blocks" do
      ErrorEvent.create!(fingerprint: "abc", error_class: "RuntimeError", message: "boom", source: "request")
      Audit.record("sign_in", actor: users(:admin_user))
      sign_in users(:admin_user)

      get admin_root_path

      assert_select "[data-people] [data-stat=admins]", text: User.where(admin: true).count.to_s
      assert_select "[data-people] svg.sparkline"
      assert_select "[data-events] svg.sparkline"
      assert_select "[data-errors] [data-stat=unresolved]", text: "1"
      assert_select "[data-recent-audit] tbody tr", minimum: 1
      assert_select "a[href='#{admin_audit_path}']"
      assert_select "a[href='#{admin_errors_path}']"
    end

    test "the request context is recorded in Current" do
      sign_in users(:admin_user)
      seen = nil
      Admin::DashboardController.class_eval do
        alias_method :original_show, :show
        define_method(:show) do
          seen = [Current.ip_address, Current.request_id]
          head :ok
        end
      end

      begin
        get admin_root_path, headers: { "X-Request-Id" => "req-123" }
      ensure
        Admin::DashboardController.class_eval do
          alias_method :show, :original_show
          remove_method :original_show
        end
      end

      assert_equal "req-123", seen.last
      assert_predicate seen.first, :present?
    end

    private

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
