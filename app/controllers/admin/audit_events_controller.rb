# frozen_string_literal: true

module Admin
  # /admin/audit: the audit log, newest first, 50 per page, filtered by GET params.
  class AuditEventsController < BaseController
    PER_PAGE = 50

    FILTERS = %i[action_name user event from to].freeze

    def index
      # permit keeps only plain strings: ?user[]=x is dropped, not a 500.
      @filters = params.slice(*FILTERS).permit(*FILTERS)
      @audit_events = AuditSearch.call(@filters).page(params[:page]).per(PER_PAGE)
    end
  end
end
