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

      # Not draft or canceled, not finished, and not over by its dates or still running (as /events lists them).
      def upcoming(organizer)
        klasses = Features.on?(:leagues) ? [Tournament, League] : [Tournament]
        events = klasses.flat_map { |klass| upcoming_of(klass, organizer) }
        events.sort_by(&:start_time).first(LIMIT)
      end

      def upcoming_of(klass, organizer)
        klass.visible.for_organizer(organizer).merge(klass.not_ended.or(klass.ongoing)).where.not(state: :finished)
          .preload(cover_attachment: :blob).order(:start_time).limit(LIMIT).to_a
      end
    end
  end
end
