# frozen_string_literal: true

module Results
  # Applies a pod's reported result as it stands, without the confirmations it was waiting for. Leagues use
  # it when the confirmation window ends with nobody contesting (tournaments never accept by themselves).
  class AcceptPending
    def self.call(pod:) # rubocop:disable Metrics/AbcSize
      Pod.transaction do
        pod.lock!
        pending = pod.pending_result
        return pod if pending.nil? || pod.disputed? || pod.finished?

        winner = pod.event_participants.find_by(id: pending["winner_id"]) if pending["type"] == "Win"
        return pod if pending["type"] == "Win" && winner.nil?

        Apply.call(pod: pod, type: pending["type"], winner: winner, by: nil, games: pending["games"])
        pod.update!(pending_result: nil, review_requested_at: nil)
        pod
      end
    end
  end
end
