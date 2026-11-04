# frozen_string_literal: true

# The public event lists (/events, /tournaments, /leagues, /circuits/:id) render shared/_event_ticket: covers and
# organizers preloaded, enrolled counts and latest published round numbers in one query each.
module EventTickets
  extend ActiveSupport::Concern

  private

  # Visible (not draft or canceled) events of a type, upcoming soonest first or past latest first, one page;
  # except: events already shown elsewhere on the page (the viewer's running now).
  def ticket_scope(klass, past:, except: [])
    scope = klass.visible.where.not(id: except.map(&:id))
    ticket_preload(past ? scope.past.order(start_time: :desc) : scope.upcoming.order(:start_time))
      .page(params[:page]).load
  end

  # The signed-in viewer's own events of a type running now (none for a visitor).
  def ongoing_tickets(klass) = ticket_preload(klass.for_player(current_user&.player).ongoing).to_a

  def ticket_preload(scope) = scope.preload(cover_attachment: :blob, event_organizer: :user)

  def enrolled_counts(events)
    Event.load_latest_published_round_numbers(events)
    EventParticipant.enrolled.where(event_id: events.map(&:id)).group(:event_id).count
  end
end
