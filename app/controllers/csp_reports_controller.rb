# frozen_string_literal: true

# Browsers post content security policy violations here (report-uri); they go to the log and to csp_reports
# (/admin/errors) so violations can be checked before the policy is enforced. No session, no CSRF token.
# Malformed bodies are ignored.
class CspReportsController < ApplicationController
  MAX_LOGGED_BYTES = 4.kilobytes

  allow_unauthenticated_access
  skip_forgery_protection
  rate_limit to: 10, within: 1.minute, with: -> { head :too_many_requests }

  def create
    Rails.logger.warn("CSP violation: #{request.raw_post.to_s.byteslice(0, MAX_LOGGED_BYTES).scrub.inspect}")
    store_report
    head :no_content
  end

  private

  def store_report
    report = JSON.parse(request.raw_post.to_s)
    report = report["csp-report"] if report.is_a?(Hash)
    return unless report.is_a?(Hash)

    CspReport.create!(document_uri: report["document-uri"], violated_directive: report["violated-directive"],
                      blocked_uri: report["blocked-uri"], user_agent: request.user_agent, ip: request.remote_ip)
  rescue JSON::ParserError
    nil
  end
end
