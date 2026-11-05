# frozen_string_literal: true

# Browsers post content security policy violations here (report-uri); they go to the log and to csp_reports
# (/admin/errors) so violations can be checked before the policy is enforced. No session, no CSRF token.
# Malformed or oversized bodies are ignored, long fields truncated; the answer is always 204.
class CspReportsController < ApplicationController
  MAX_LOGGED_BYTES = 4.kilobytes
  MAX_BODY_BYTES = 64.kilobytes
  MAX_FIELD_LENGTH = 2048

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
    report = parsed_report or return

    CspReport.create!(document_uri: field(report["document-uri"]),
                      violated_directive: field(report["violated-directive"]),
                      blocked_uri: field(report["blocked-uri"]), user_agent: field(request.user_agent),
                      ip: request.remote_ip)
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  # The `csp-report` hash, or nil for an oversized or malformed body.
  def parsed_report
    body = request.raw_post.to_s
    return if body.bytesize > MAX_BODY_BYTES

    report = JSON.parse(body)
    report = report["csp-report"] if report.is_a?(Hash)
    report if report.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def field(value)
    value&.to_s&.first(MAX_FIELD_LENGTH)
  end
end
