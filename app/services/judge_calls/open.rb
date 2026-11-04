# frozen_string_literal: true

module JudgeCalls
  # Opens a judge call and tells the event's organizers and judges. A pod has one open call at most
  # (a unique index): when another request opened it first, that call is returned and nobody is told
  # twice. The savepoint keeps a caller's transaction usable after the refused insert.
  class Open
    def self.call(event:, reason:, pod: nil, participant: nil)
      JudgeCall.transaction(requires_new: true) do
        call = JudgeCall.create!(event: event, pod: pod, participant: participant,
                                 reason: reason.to_s.truncate(JudgeCall::REASON_MAX_LENGTH))
        Notify.staff(event, kind: "judge_call", subject: call)
        call
      end
    rescue ActiveRecord::RecordNotUnique
      JudgeCall.find_by!(pod: pod, status: "open")
    end
  end
end
