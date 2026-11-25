# frozen_string_literal: true

module Leagues
  # A player leaves the league, by themselves or dropped by the organizer. Refused while they sit at a full
  # table still to finish (it must be reported or cancelled first). A table they opened and still waits is
  # closed, and their seat at someone else's is freed. Before the league starts the registration is removed
  # and the waitlist moves up; afterwards it is a drop: the games played stay in the standings.
  class Leave
    def self.call(league:, participant:, by:, reason: "drop")
      League.transaction do
        participant.lock!
        free_seat(participant)
        if league.playing? || league.finished?
          Registrations::Drop.call(participant: participant, by: by, reason: reason)
        else
          remove(league, participant)
        end
      end
    end

    def self.free_seat(participant) # rubocop:disable Metrics/MethodLength
      seat = LeagueTableSeat.active.find_by(event_participant_id: participant.id) or return
      table = seat.league_table
      table.lock!
      raise Tables::NotAllowed, "finish_first" if table.filled?

      if table.opener_id == participant.id
        table.release_seats!
        table.update!(state: "closed")
      else
        seat.destroy!
        table.touch # rubocop:disable Rails/SkipsModelValidations -- pushes the list to the page
      end
    end

    def self.remove(league, participant)
      league.with_lock do
        freed_place = participant.enrolled?
        participant.destroy!
        league.fill_from_waitlist!(freed_place: freed_place)
      end
    end
    private_class_method :free_seat, :remove
  end
end
