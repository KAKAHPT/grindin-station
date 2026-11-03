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

    def check!
      refuse("not_seated") unless @pod.seated?(@participant)
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
      winner = @pod.event_participants.find(pending["winner_id"]) if pending["type"] == "Win"
      Apply.call(pod: @pod, type: pending["type"], winner: winner, by: nil)
      @pod.update!(pending_result: nil, review_requested_at: nil)
    end
  end
end
