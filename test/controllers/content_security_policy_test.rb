# frozen_string_literal: true

require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  HEADER = "Content-Security-Policy-Report-Only"

  test "pages carry a report-only policy whose nonce is on the importmap scripts" do
    get root_path

    assert_response :success
    assert_nil response.headers["Content-Security-Policy"]
    policy = response.headers[HEADER]
    assert_includes policy, "default-src 'self'"
    assert_includes policy, "object-src 'none'"
    assert_includes policy, "frame-ancestors 'none'"
    assert_includes policy, "connect-src 'self' ws: wss:"
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
end
