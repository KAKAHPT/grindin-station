# frozen_string_literal: true

module Admin
  # /admin/circuits: every circuit, newest first, with its organizer and event count; Featured is editable here.
  class CircuitsController < BaseController
    PER_PAGE = 50

    def index
      @circuits = Circuit.includes(event_organizer: :user).order(created_at: :desc).page(params[:page]).per(PER_PAGE)
      @events_counts = Event.where(circuit_id: @circuits.map(&:id)).group(:circuit_id).count
    end

    def featured
      circuit = Circuit.find(params.expect(:id))
      circuit.update_columns(featured: !circuit.featured, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Audit.record("featured_changed", subject: circuit, featured: circuit.featured)
      redirect_to admin_circuits_path(page: params[:page].presence), notice: t("admin.circuits.featured_saved")
    end
  end
end
