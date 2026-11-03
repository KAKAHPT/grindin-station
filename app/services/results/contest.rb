# frozen_string_literal: true

module Results
  # A seated player contests the pod's pending or applied result: the pod is disputed until
  # staff reports it, a judge is called and the table is told.
  class Contest
    def self.call(pod:, participant:, reason:)
      new(pod: pod, participant: participant, reason: reason).call
    end

    def initialize(pod:, participant:, reason:)
      @pod = pod
      @participant = participant
      @reason = reason
    end

    def call
      Pod.transaction do
        @pod.lock!
        check!
        @pod.update!(disputed: true)
        judge_call = JudgeCalls::Open.call(event: @pod.event, pod: @pod, participant: @participant,
                                           reason: "Result contested: #{@reason}")
        Notify.participants(@pod, kind: "result_contested", subject: judge_call)
        @pod
      end
    end

    private

    def check!
      refuse("self_report_disabled") unless @pod.event.self_report_enabled
      refuse("not_seated") unless @pod.seated?(@participant)
      refuse("disputed") if @pod.disputed?
      refuse("nothing_to_contest") unless @pod.pending_result || @pod.finished?
      refuse("reason_required") if @reason.blank?
    end

    def refuse(key)
      raise NotAllowed, key
    end
  end
end
