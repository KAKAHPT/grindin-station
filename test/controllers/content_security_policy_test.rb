# frozen_string_literal: true

require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  include RateLimitStore

  HEADER = "Content-Security-Policy"

  test "pages carry an enforced policy whose nonce is on the importmap scripts" do
    get root_path

    assert_response :success
    assert_nil response.headers["Content-Security-Policy-Report-Only"], "enforced outside development"
    policy = response.headers[HEADER]
    assert_includes policy, "default-src 'self'"
    assert_includes policy, "object-src 'none'"
    assert_includes policy, "frame-ancestors 'none'"
    assert_includes policy, "connect-src 'self';"
    assert_includes policy, "report-uri /csp-reports"
    nonce = policy[/'nonce-([^']+)'/, 1]
    assert nonce
    assert_select "script[type=importmap][nonce=?]", nonce
    assert_select "script[type=module][nonce=?]", nonce
  end

  test "each response gets its own nonce" do
    nonces =
      Array.new(2) do
        get root_path
        response.headers[HEADER][/'nonce-([^']+)'/, 1]
      end

    assert_equal 2, nonces.uniq.size
  end

  test "violation reports are logged without a session and rate-limited" do
    log = StringIO.new
    logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    with_memory_rate_limit_store do
      post csp_reports_path, params: '{"csp-report":{"violated-directive":"script-src"}}',
                             headers: { "Content-Type" => "application/csp-report" }
      assert_response :no_content

      10.times { post csp_reports_path, params: "{}", headers: { "Content-Type" => "application/csp-report" } }
      assert_response :too_many_requests
    end
    assert_includes log.string, "CSP violation: " + %({"csp-report":{"violated-directive":"script-src"}}).inspect
  ensure
    Rails.logger = logger
  end
end
