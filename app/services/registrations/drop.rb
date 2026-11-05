# frozen_string_literal: true

module Registrations
  # Drops a participant (reason "drop" or "no_show"). Before the swiss starts the first on the
  # waitlist takes the freed place. An unpublished round is rebuilt (EventParticipant#rebuild_round);
  # after publication the player keeps the seat and is left out of the next pairing.
  # `by` is the audited actor.
  class Drop
    def self.call(participant:, by:, reason: "drop")
      event = participant.event
      event.with_lock do
        frees_a_place = participant.enrolled?
        participant.update!(dropped: true, dropped_at: Time.current, drop_reason: reason,
                            waitlisted: false, waitlist_position: nil)
        event.fill_from_waitlist!(freed_place: frees_a_place) unless event.points_locked?
      end
      Audit.record(:participant_dropped, actor: by, subject: participant, event: event,
                                         participant_id: participant.id, reason: reason)
      participant
    end
  end
end
