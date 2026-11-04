# frozen_string_literal: true

module JudgeCalls
  # Opens a judge call and tells the event's organizers and judges. A pod has one open call at most
  # (a unique index): when the pod already has one, the new reason is added to it and the staff are
  # told again. The savepoint keeps a caller's transaction usable after the refused insert.
  class Open
    def self.call(event:, reason:, pod: nil, participant: nil)
      JudgeCall.transaction do
        call = create_or_add(event: event, reason: reason, pod: pod, participant: participant)
        Notify.staff(event, kind: "judge_call", subject: call)
        call
      end
    end

    def self.create_or_add(event:, reason:, pod:, participant:)
      JudgeCall.transaction(requires_new: true) do
        JudgeCall.create!(event: event, pod: pod, participant: participant, reason: limit(reason))
      end
    rescue ActiveRecord::RecordNotUnique
      open = JudgeCall.find_by!(pod: pod, status: "open")
      open.tap { open.update!(reason: limit("#{open.reason}\n#{reason}")) }
    end

    def self.limit(reason)
      reason.to_s.truncate(JudgeCall::REASON_MAX_LENGTH)
    end
    private_class_method :create_or_add, :limit
  end
end
