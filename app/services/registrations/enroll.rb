# frozen_string_literal: true

module Registrations
  # Signs a player up: refused once the swiss started; when the event is full the player joins the
  # waitlist (when enabled) or is refused. The caller checks the terms were accepted.
  class Enroll
    def self.call(event:, player:, decklist: nil)
      event.with_lock do
        raise Closed if event.points_locked?

        attributes = { event: event, player: player, decklist: decklist, accepted_terms: true }
        if event.playing_participants_count >= event.maximum_participants
          raise Full unless event.waitlist_enabled

          attributes[:waitlisted] = true
          attributes[:waitlist_position] = event.event_participants.maximum(:waitlist_position).to_i + 1
        end
        EventParticipant.create!(attributes)
      end
    end
  end
end
