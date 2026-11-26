# frozen_string_literal: true

module Leagues
  # A league game got its result (reported and confirmed, entered or corrected by the organizer). The first
  # time, the game's round is stamped as ended and its players are free for another table; every time, the
  # league's scores are replayed. Called by Results::Apply for LeagueGameRound pods.
  module SettlePod
    def self.call(pod)
      pod = Pod.find(pod.id) # fresh: the caller's copy may hold the results as they were before
      league = pod.round.event
      close(pod) if pod.finished?
      Scoring::PointWager.new(league).recalculate_all!
      Lifecycle.settle_closing(league)
    end

    def self.close(pod)
      now = Time.current
      pod.round.update_columns(finished_at: now, updated_at: now) if pod.round.finished_at.nil? # rubocop:disable Rails/SkipsModelValidations
      table = pod.league_table or return

      table.release_seats!
      # A result everyone accepted answers a cancellation request still waiting.
      table.update!(cancel_state: "refused", cancel_decided_at: now) if table.cancel_pending?
    end
    private_class_method :close
  end
end
