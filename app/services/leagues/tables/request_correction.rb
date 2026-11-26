# frozen_string_literal: true

module Leagues
  module Tables
    # A player of a league game says its result (final, or reported and waiting for a confirmation) is wrong,
    # with a reason. The league's staff then
    # correct it or keep it (ResolveCorrection). Possible until the league's cut starts.
    class RequestCorrection
      OPEN_STATES = %w[play closing closed].freeze

      def self.call(table:, participant:, reason:)
        LeagueTable.transaction do
          table.lock!
          check!(table, participant, reason)
          table.update!(correction_state: "pending", correction_reason: reason.to_s.strip,
                        correction_requested_by: participant, correction_requested_at: Time.current,
                        correction_decided_by: nil, correction_decided_at: nil)
          Notify.staff(table.league, kind: "league_correction_requested", subject: table.pod)
          table
        end
      end

      def self.check!(table, participant, reason) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity -- one line per guard
        raise NotAllowed, "not_finished" unless table.filled? && (table.pod&.finished? || table.pod&.pending_result)
        raise NotAllowed, "league_over" unless table.league.state.in?(OPEN_STATES)
        raise NotAllowed, "not_member" unless table.seats.exists?(event_participant_id: participant&.id)
        raise NotAllowed, "reason_required" if reason.to_s.strip.empty?
        raise NotAllowed, "already_requested" if table.correction_pending?
        # The staff answered this player about this game already: their answer stands.
        raise NotAllowed, "already_answered" if table.correction_requested_by_id == participant.id
      end
      private_class_method :check!
    end
  end
end
