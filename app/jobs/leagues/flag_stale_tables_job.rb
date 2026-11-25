# frozen_string_literal: true

module Leagues
  # A full table with no result a week after it filled: the league's staff get one notification to decide
  # it (enter a result or cancel). Nothing is cancelled by itself. Runs daily (config/recurring.yml).
  class FlagStaleTablesJob < ApplicationJob
    STALE_AFTER = 7.days

    def perform
      LeagueTable.filled.where(stale_notified_at: nil, filled_at: ..STALE_AFTER.ago)
        .includes(:league, pod: [:seatings, { round: :results }]).find_each do |table|
        next unless table.in_play?

        Notify.staff(table.league, kind: "league_table_stale", subject: table.pod)
        table.update!(stale_notified_at: Time.current)
      end
    end
  end
end
