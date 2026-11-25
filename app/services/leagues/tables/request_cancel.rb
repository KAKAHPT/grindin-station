# frozen_string_literal: true

module Leagues
  module Tables
    # A player of a full table asks the organizer to cancel it, with a reason. The four stay at the table
    # until the organizer decides (DecideCancel) or a result is accepted.
    class RequestCancel
      def self.call(table:, participant:, reason:)
        LeagueTable.transaction do
          table.lock!
          check!(table, participant, reason)
          table.update!(cancel_state: "pending", cancel_reason: reason.to_s.strip, cancel_requested_by: participant,
                        cancel_requested_at: Time.current, cancel_decided_by: nil, cancel_decided_at: nil)
          Notify.staff(table.league, kind: "league_cancel_requested", subject: table.pod)
          table
        end
      end

      def self.check!(table, participant, reason)
        raise NotAllowed, "not_in_play" unless table.in_play?
        raise NotAllowed, "not_member" unless table.seats.exists?(event_participant_id: participant&.id)
        raise NotAllowed, "reason_required" if reason.to_s.strip.empty?
        raise NotAllowed, "already_requested" if table.cancel_pending?
      end
      private_class_method :check!
    end
  end
end
