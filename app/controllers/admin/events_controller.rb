# frozen_string_literal: true

module Admin
  # /admin/events: every tournament and league, newest first; only Featured is editable here.
  class EventsController < BaseController
    PER_PAGE = 50

    def index
      @events = Event.includes(event_organizer: :user).order(created_at: :desc).page(params[:page]).per(PER_PAGE)
    end

    def featured
      event = Event.find(params.expect(:id))
      event.update!(featured: !event.featured)
      Audit.record("featured_changed", subject: event, event: event, featured: event.featured)
      redirect_to admin_events_path(page: params[:page]), notice: t("admin.events.featured_saved")
    end
  end
end
