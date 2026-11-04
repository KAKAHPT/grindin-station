# frozen_string_literal: true

# The public event lists (/events, /tournaments, /leagues, /circuits/:id) render shared/_event_ticket: covers and
# organizers preloaded, enrolled counts in one query.
module EventTickets
  extend ActiveSupport::Concern

  private

  # Visible (not draft or canceled) events of a type, upcoming soonest first or past latest first.
  def ticket_scope(klass, past:)
    scope = klass.visible
    ticket_preload(past ? scope.past.order(start_time: :desc) : scope.upcoming.order(:start_time))
  end

  def ticket_preload(scope) = scope.preload(cover_attachment: :blob, event_organizer: :user)

  def enrolled_counts(events)
    EventParticipant.enrolled.where(event_id: events.map(&:id)).group(:event_id).count
  end
end
