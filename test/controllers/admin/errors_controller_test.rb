# frozen_string_literal: true

require "test_helper"

module Admin
  class ErrorsControllerTest < ActionDispatch::IntegrationTest
    setup do
      2.times { occurrence("aaa", "boom") }
      occurrence("bbb", "other failure")
      CspReport.create!(violated_directive: "script-src", blocked_uri: "https://evil.example", document_uri: "/")
      Audit.record("rate_limited", actor: nil, controller: "sessions", action: "create", path: "/session")
      post session_path, params: { session: { email_address: users(:admin_user).email_address,
                                              password: "password123" } }
    end

    test "lists one row per unresolved fingerprint with its count, plus CSP and rate limits" do
      get admin_errors_path

      assert_response :success
      assert_select "tr[data-error='aaa'] td[data-col=count]", text: "2"
      assert_select "tr[data-error='aaa']", text: /RuntimeError/
      assert_select "tr[data-error='bbb']"
      assert_select "[data-csp] tbody tr", text: %r{script-src.*https://evil.example}m
      assert_select "[data-rate-limits] tbody tr", text: /sessions#create/
    end

    test "resolve hides the group and audits it; a new occurrence brings it back" do
      post resolve_admin_error_path("aaa")

      assert_redirected_to admin_errors_path
      assert ErrorEvent.where(fingerprint: "aaa").all?(&:resolved_at)
      audit = AuditEvent.recent.first
      assert_equal ["error_resolved", users(:admin_user), { "fingerprint" => "aaa" }],
                   [audit.action, audit.actor_user, audit.data]

      get admin_errors_path

      assert_select "tr[data-error='aaa']", count: 0
      assert_select "tr[data-error='bbb']"

      occurrence("aaa", "boom again")
      get admin_errors_path

      assert_select "tr[data-error='aaa'] td[data-col=count]", text: "1"
    end

    test "resolving an already resolved group writes no audit" do
      post resolve_admin_error_path("aaa")

      assert_no_difference -> { AuditEvent.where(action: "error_resolved").count } do
        post resolve_admin_error_path("aaa")
      end
    end

    test "shows the latest occurrence with its backtrace and the last occurrences" do
      get admin_error_path("aaa")

      assert_response :success
      assert_select "pre", text: %r{app/models/thing.rb:1}
      assert_select "[data-occurrences] tbody tr", count: 2
    end

    test "an unknown fingerprint is a 404" do
      get admin_error_path("nope")

      assert_response :not_found
    end

    private

    def occurrence(fingerprint, message)
      ErrorEvent.create!(fingerprint: fingerprint, error_class: "RuntimeError", message: message, source: "request",
                         backtrace: "app/models/thing.rb:1\napp/models/thing.rb:2", path: "/things",
                         request_id: "req-1", user_id: users(:organizer_user).id)
    end
  end
end
