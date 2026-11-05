# frozen_string_literal: true

require "test_helper"

class CspReportsControllerTest < ActionDispatch::IntegrationTest
  HEADERS = { "Content-Type" => "application/csp-report", "User-Agent" => "TestBrowser/1" }.freeze

  test "a valid report is stored" do
    body = { "csp-report" => { "document-uri" => "https://grindin.test/e/1", "violated-directive" => "script-src",
                               "blocked-uri" => "https://evil.test/x.js" } }.to_json

    assert_difference -> { CspReport.count }, 1 do
      post csp_reports_path, params: body, headers: HEADERS
    end

    assert_response :no_content
    report = CspReport.last
    assert_equal "https://grindin.test/e/1", report.document_uri
    assert_equal "script-src", report.violated_directive
    assert_equal "https://evil.test/x.js", report.blocked_uri
    assert_equal "TestBrowser/1", report.user_agent
    assert_equal "127.0.0.1", report.ip
  end

  test "garbage is ignored" do
    assert_no_difference -> { CspReport.count } do
      post csp_reports_path, params: "not json{", headers: HEADERS
      assert_response :no_content
      post csp_reports_path, params: "[1,2]", headers: HEADERS
      assert_response :no_content
      post csp_reports_path, params: '{"other":1}', headers: HEADERS
      assert_response :no_content
    end
  end
end
