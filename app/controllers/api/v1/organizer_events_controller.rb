# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/organizers/:handle/events: an organizer's public tournaments and leagues that are not over yet,
    # soonest first (see Feeds::OrganizerEvents). The same events /events lists with ?organizer=:handle, so this is
    # public even while the organizer pages (/o/:handle) are paused. cedhpt.com reads it for its events grid.
    # An unknown, anonymised or suspended organizer is not found.
    class OrganizerEventsController < BaseController
      LIMIT = 24

      def index
        user = User.find_by!(handle: params.expect(:handle))
        organizer = user.event_organizer
        raise ActiveRecord::RecordNotFound if organizer.nil? || user.anonymized? || organizer.suspended?

        render json: Feeds::OrganizerEvents.call(organizer, events: upcoming(organizer), base_url: request.base_url)
      end

      private

      # Not draft, canceled or finished, and not over by its dates or still running (as /events lists them).
      # Tournaments and leagues in one query: both state enums map these states to the same integers
      # (draft 0, swiss/play 3, single_elimination/finals 4, finished 5, canceled 6), so Event filters them by value.
      def upcoming(organizer)
        states = Tournament.states
        types = Features.on?(:leagues) ? %w[Tournament League] : %w[Tournament]
        base = Event.where(type: types, event_organizer: organizer)
          .where.not(state: states.values_at(*Event::HIDDEN_STATES, "finished"))
        base.where(end_time: Time.current..).or(base.where(state: states.values_at("swiss", "single_elimination")))
          .preload(cover_attachment: :blob).order(:start_time).limit(LIMIT).to_a
      end
    end
  end
end
