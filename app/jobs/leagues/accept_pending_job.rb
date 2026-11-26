# frozen_string_literal: true

module Leagues
  # In a league whose results wait for another player's confirmation: a result nobody confirmed or said was
  # wrong within League::CONFIRMATION_WINDOW is accepted. One with a correction asked waits for the staff.
  # Runs every five minutes (config/recurring.yml).
  class AcceptPendingJob < ApplicationJob
    def perform
      Pod.joins(round: :event)
        .where(events: { type: "League" }, disputed: false)
        .where.not(pending_result: nil)
        .where(pods: { reported_at: ..League::CONFIRMATION_WINDOW.ago })
        .where.not(id: LeagueTable.correction_pending.select(:pod_id))
        .find_each { |pod| Results::AcceptPending.call(pod: pod) }
    end
  end
end
