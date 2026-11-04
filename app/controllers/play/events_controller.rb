# frozen_string_literal: true

module Play
  # The public event page (/t/:slug): details, enrolment and the lists of enrolled and waiting players.
  class EventsController < BaseController
    public_actions :show

    def show
      participants = current_event.event_participants.playing.preload(player: :user)
      @enrolled = participants.where(waitlisted: false).order(:created_at, :id).to_a
      @waitlist = participants.where(waitlisted: true).order(:waitlist_position).to_a
      @round_number = current_round&.number
      @staff_role = current_user&.staff_role_for(current_event)
    end
  end
end
