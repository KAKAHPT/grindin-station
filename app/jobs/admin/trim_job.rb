# frozen_string_literal: true

module Admin
  # Nightly retention: audit events 12 months, error events 90 days, CSP reports 30 days.
  class TrimJob < ApplicationJob
    def perform
      audit = AuditEvent.where(created_at: ...12.months.ago).delete_all
      errors = ErrorEvent.where(created_at: ...90.days.ago).delete_all
      csp = CspReport.where(created_at: ...30.days.ago).delete_all
      Rails.logger.info("Admin::TrimJob deleted audit_events=#{audit} error_events=#{errors} csp_reports=#{csp}")
    end
  end
end
