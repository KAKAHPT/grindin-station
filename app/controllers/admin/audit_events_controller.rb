# frozen_string_literal: true

module Admin
  # /admin/audit: the audit log, newest first, 50 per page, filtered by GET params.
  class AuditEventsController < BaseController
    PER_PAGE = 50

    def index
      @audit_events = AuditSearch.call(params).page(params[:page]).per(PER_PAGE)
    end
  end
end
