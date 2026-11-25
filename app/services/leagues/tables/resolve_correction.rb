# frozen_string_literal: true

module Leagues
  module Tables
    # The staff answer a correction request: `result` is the winner's participant id, "draw", or "keep" (the
    # reported result stands). A new result rewrites the game and replays the league's scores (Results::Apply).
    class ResolveCorrection
      def self.call(table:, by:, result:) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
        LeagueTable.transaction do
          table.lock!
          raise NotAllowed, "nothing_pending" unless table.correction_pending?
          raise NotAllowed, "league_over" unless table.league.state.in?(RequestCorrection::OPEN_STATES)

          kept = result.to_s == "keep"
          apply(table.pod, result, by) unless kept
          table.update!(correction_state: kept ? "kept" : "corrected", correction_decided_by: by,
                        correction_decided_at: Time.current)
          Notify.participants(table.pod, kind: "league_correction_#{kept ? 'kept' : 'done'}", subject: table.pod)
          Lifecycle.settle_closing(table.league)
          table
        end
      end

      def self.apply(pod, result, by)
        winner = pod.event_participants.find_by(id: result) unless result.to_s == "draw"
        raise NotAllowed, "invalid_result" if winner.nil? && result.to_s != "draw"

        Results::Apply.call(pod: pod, type: winner ? "Win" : "Draw", winner: winner, by: by)
      end
      private_class_method :apply
    end
  end
end
