# frozen_string_literal: true

module Results
  # Pending results nobody confirmed within the event's timeout go to staff for review;
  # they are never accepted automatically. Runs every minute (config/recurring.yml).
  class ExpirePendingJob < ApplicationJob
    def perform
      now = Time.current
      Pod.joins(round: :event)
        .where.not(pending_result: nil)
        .where(review_requested_at: nil)
        .where("pods.reported_at < CAST(? AS timestamp) - make_interval(mins => events.confirmation_timeout_minutes)",
               now)
        .update_all(review_requested_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
