# frozen_string_literal: true

module Leagues
  # The league's steps the organizer takes (start, close, reopen, cut, finish) and the one that happens by
  # itself: a closing league is closed once its last table is settled.
  module Lifecycle
    extend self

    def settle_closing(league)
      return unless league.closing?
      return if league.league_tables.filled.includes(pod: [:seatings, { round: :results }]).any?(&:in_play?)

      league.update!(state: :closed)
    end
  end
end
