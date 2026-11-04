# frozen_string_literal: true

module Results
  # A seated player confirms the pod's pending result. Once enough players have (two for "one",
  # the whole pod for "all") it is applied; the reporter and confirmations stay for audit.
  class Confirm
    def self.call(pod:, participant:)
      new(pod: pod, participant: participant).call
    end

    def initialize(pod:, participant:)
      @pod = pod
      @participant = participant
    end

    def call
      Pod.transaction do
        @pod.lock!
        check!
        @pod.update!(confirmations: @pod.confirmations.merge(@participant.id => Time.current.iso8601))
        apply! if @pod.confirmations.size >= required
        @pod
      end
    end

    private

    # A staff result entered while the report was pending wins: the stale pending is never applied.
    def check! # rubocop:disable Metrics/AbcSize -- one line per guard
      refuse("self_report_disabled") unless @pod.event.self_report_enabled
      refuse("not_seated") unless @pod.seated?(@participant)
      refuse("already_finished") if @pod.finished?
      refuse("disputed") if @pod.disputed?
      refuse("nothing_pending") if @pod.pending_result.nil?
      refuse("already_confirmed") if @pod.confirmations.key?(@participant.id)
    end

    def refuse(key)
      raise NotAllowed, key
    end

    def required
      { "none" => 1, "one" => 2 }.fetch(@pod.event.result_confirmation, @pod.size)
    end

    def apply!
      pending = @pod.pending_result
      if pending["type"] == "Win"
        winner = @pod.event_participants.find_by(id: pending["winner_id"])
        refuse("invalid_winner") if winner.nil?
      end
      Apply.call(pod: @pod, type: pending["type"], winner: winner, by: nil)
      @pod.update!(pending_result: nil, review_requested_at: nil)
    end
  end
end
