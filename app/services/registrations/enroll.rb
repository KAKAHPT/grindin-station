# frozen_string_literal: true

module Registrations
  # Signs a player up: refused once the swiss started; when the event is full the player joins the
  # waitlist (when enabled) or is refused. The caller checks the terms were accepted.
  class Enroll
    def self.call(event:, player:, decklist: nil)
      event.with_lock do
        guard!(event, player)

        attributes = { event: event, player: player, decklist: decklist, accepted_terms: true }
        if event.playing_participants_count >= event.maximum_participants
          raise Full unless event.waitlist_enabled

          attributes[:waitlisted] = true
          attributes[:waitlist_position] = event.event_participants.maximum(:waitlist_position).to_i + 1
        end
        EventParticipant.create!(attributes)
      end
    end

    def self.guard!(event, player)
      raise ArgumentError, "a player is required" if player.nil?
      # Self-registration only while the organizer keeps it open (closing registrations must stick).
      raise Closed unless event.registration_open?
      raise AlreadyEnrolled if event.event_participants.exists?(player: player)
    end
    private_class_method :guard!
  end
end
