# frozen_string_literal: true

module JudgeCalls
  # Opens a judge call and tells the event's organizers and judges.
  class Open
    def self.call(event:, reason:, pod: nil, participant: nil)
      JudgeCall.transaction do
        call = JudgeCall.create!(event: event, pod: pod, participant: participant, reason: reason)
        Notify.staff(event, kind: "judge_call", subject: call)
        call
      end
    end
  end
end
