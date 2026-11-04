# frozen_string_literal: true

module Play
  # The public event page (/t/:slug): details, registration counts and, for a participant, their own entry
  # (decklist, cancel). Other players' names and decklists are not listed here.
  class EventsController < BaseController
    public_actions :show

    def show
      counts = current_event.event_participants.playing.group(:waitlisted).count
      @enrolled_count = counts.fetch(false, 0)
      @waitlist_count = counts.fetch(true, 0)
      @decklist_locked = current_event.rounds.published.exists?
      @staff_role = current_user&.staff_role_for(current_event)
    end
  end
end
