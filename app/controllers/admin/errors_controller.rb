# frozen_string_literal: true

module Admin
  # /admin/errors: unresolved error groups, CSP reports and rate limits; one group's occurrences; resolve.
  class ErrorsController < BaseController
    OCCURRENCES = 20

    def index
      @groups = ErrorGroups.unresolved
      @csp_reports = ErrorGroups.csp_reports
      @rate_limits = ErrorGroups.rate_limits
    end

    def show
      @occurrences = ErrorEvent.where(fingerprint: params[:fingerprint]).order(created_at: :desc)
        .limit(OCCURRENCES).to_a
      return head :not_found if @occurrences.empty?

      @latest = @occurrences.first
      @user = User.find_by(id: @latest.user_id)
    end

    def resolve
      ErrorEvent.unresolved.where(fingerprint: params[:fingerprint]).update_all(resolved_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Audit.record("error_resolved", fingerprint: params[:fingerprint])
      redirect_to admin_errors_path, notice: t("admin.errors.resolved")
    end
  end
end
