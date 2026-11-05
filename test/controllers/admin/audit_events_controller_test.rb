# frozen_string_literal: true

require "test_helper"

module Admin
  class AuditEventsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = users(:admin_user)
      @event = events(:standard_tournament)
      Audit.record("sign_in", actor: @admin)
      Audit.record("staff_added", actor: users(:organizer_user), event: @event, user_id: "u-1", role: "judge")
      sign_in @admin
    end

    test "a non-admin gets a 404" do
      delete session_path
      sign_in users(:organizer_user)

      get admin_audit_path

      assert_response :not_found
    end

    test "lists audit events newest first with their details" do
      get admin_audit_path

      assert_response :success
      rows = css_select("table.ctable tbody tr").map(&:text)
      staff = rows.index { |text| text.include?("staff_added") }
      sign_in_row = rows.rindex { |text| text.include?("sign_in") }
      assert_operator staff, :<, sign_in_row
      assert_includes rows[staff], "role: judge"
      assert_includes rows[staff], users(:organizer_user).email_address
    end

    test "filters by action" do
      get admin_audit_path, params: { action_name: "sign_in" }

      assert_select "table.ctable tbody tr", count: AuditEvent.for_action("sign_in").count
      assert_select "table.ctable tbody", text: /staff_added/, count: 0
    end

    test "filters by actor e-mail and event name" do
      get admin_audit_path, params: { user: "ADMIN@" }

      assert_select "table.ctable tbody tr", count: AuditEvent.where(actor_user: @admin).count
      assert_select "table.ctable tbody", text: /staff_added/, count: 0

      get admin_audit_path, params: { event: @event.name.upcase }

      assert_select "table.ctable tbody tr", count: 1
      assert_select "table.ctable tbody tr", text: /staff_added/
    end

    test "filters by date range" do
      AuditEvent.where(action: "sign_in").update_all(created_at: 10.days.ago) # rubocop:disable Rails/SkipsModelValidations

      get admin_audit_path, params: { from: 2.days.ago.to_date.iso8601, to: Date.current.iso8601 }

      assert_select "table.ctable tbody", text: /sign_in/, count: 0
      assert_select "table.ctable tbody tr", text: /staff_added/

      get admin_audit_path, params: { from: 11.days.ago.to_date.iso8601, to: 9.days.ago.to_date.iso8601 }

      assert_select "table.ctable tbody", text: /staff_added/, count: 0
    end

    test "array params are ignored, not an error" do
      get admin_audit_path, params: { user: ["admin"], from: ["2026-01-01"] }

      assert_response :success
      assert_select "table.ctable tbody tr", count: AuditEvent.count
    end

    private

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
