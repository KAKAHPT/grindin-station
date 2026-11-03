# frozen_string_literal: true

module Registrations
  # Drops a participant (reason "drop" or "no_show"). Before the swiss starts the first on the
  # waitlist takes the freed place. An unpublished round is rebuilt (EventParticipant#rebuild_round);
  # after publication the player keeps the seat and is left out of the next pairing.
  # `by` is unused until notifications (Task 6).
  class Drop
    def self.call(participant:, by:, reason: "drop") # rubocop:disable Lint/UnusedMethodArgument
      event = participant.event
      event.with_lock do
        frees_a_place = participant.enrolled?
        participant.update!(dropped: true, dropped_at: Time.current, drop_reason: reason,
                            waitlisted: false, waitlist_position: nil)
        fill_from_waitlist(event, frees_a_place) unless event.points_locked?
      end
      participant
    end

    def self.fill_from_waitlist(event, frees_a_place)
      event.event_participants.waitlist.first&.promote! if frees_a_place
      event.renumber_waitlist!
    end

    private_class_method :fill_from_waitlist
  end
end
