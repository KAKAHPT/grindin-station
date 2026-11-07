# frozen_string_literal: true

require "test_helper"

# The browser-side protections every response carries (the CSP has its own test).
class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "the Permissions-Policy and the default hardening headers are set" do
    get root_path

    policy = response.headers["Permissions-Policy"]
    assert_includes policy, "camera=()"
    assert_includes policy, "microphone=()"
    assert_includes policy, "geolocation=()"
    assert_includes policy, "fullscreen=(self)"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
  end
end
