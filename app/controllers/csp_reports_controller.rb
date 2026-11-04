# frozen_string_literal: true

# Browsers post content security policy violations here (report-uri); they go to the log so an event
# day's violations can be checked before the policy is enforced. No session, no CSRF token.
class CspReportsController < ApplicationController
  MAX_LOGGED_BYTES = 4.kilobytes

  allow_unauthenticated_access
  skip_forgery_protection
  rate_limit to: 10, within: 1.minute, with: -> { head :too_many_requests }

  def create
    Rails.logger.warn("CSP violation: #{request.raw_post.to_s.byteslice(0, MAX_LOGGED_BYTES)}")
    head :no_content
  end
end
