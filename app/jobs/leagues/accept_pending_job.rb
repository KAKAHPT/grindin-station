# frozen_string_literal: true

module Leagues
  # A league result reported and not contested within the league's confirmation window (24 hours by default)
  # is accepted. Runs every five minutes (config/recurring.yml).
  class AcceptPendingJob < ApplicationJob
    def perform
      Pod.joins(round: :event)
        .where(events: { type: "League" }, disputed: false)
        .where.not(pending_result: nil)
        .where("pods.reported_at < CAST(? AS timestamp) - make_interval(mins => events.confirmation_timeout_minutes)",
               Time.current)
        .find_each { |pod| Results::AcceptPending.call(pod: pod) }
    end
  end
end
