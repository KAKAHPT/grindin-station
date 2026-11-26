# frozen_string_literal: true

module Leagues
  # The league's steps the organizer takes (start, close, reopen, cut, finish) and the one that happens by
  # itself: a closing league is closed once its last table is settled.
  module Lifecycle
    extend self

    class NotAllowed < StandardError; end

    def start(league, by:)
      refuse("not_startable") unless league.registration_open? || league.registration_closed?
      move(league, :play, by)
    end

    # No table can be opened or joined any more. Waiting tables are voided; the full ones play to the end,
    # and the league is closed when the last of them is settled (at once when there is none).
    def close(league, by:) # rubocop:disable Metrics/MethodLength
      refuse("not_in_play") unless league.play?
      League.transaction do
        # Each table is locked and looked at again: one a 4th player filled meanwhile plays to the end.
        league.league_tables.waiting.find_each do |table|
          table.lock!
          next unless table.waiting?

          table.release_seats!
          table.update!(state: "closed")
        end
        move(league, :closing, by)
        settle_closing(league)
      end
    end

    def settle_closing(league)
      return unless league.closing?
      return if league.league_tables.filled.includes(pod: [:seatings, { round: :results }]).any?(&:in_play?)
      return if league.league_tables.correction_pending.exists?

      league.update!(state: :closed)
      Audit.record(:event_state_changed, subject: league, event: league, from: "closing", to: "closed")
    end

    # Back to play, while the cut has not started.
    def reopen(league, by:)
      refuse("not_closed") unless league.closing? || league.closed?
      refuse("cut_started") if league.rounds.exists?(type: "LeagueCutRound")
      move(league, :play, by)
    end

    # The top cut, of the largest size the qualified field fills; with no cut possible (or none wanted) the
    # league finishes by the standings.
    def make_cut(league, by:)
      refuse("not_closed") unless league.closed?
      refuse("corrections_pending") if league.league_tables.correction_pending.exists?
      size = league.cut_size_for_field
      return finish(league, by: by) if size.zero?

      league.update_column(:top_cut_size, size) # rubocop:disable Rails/SkipsModelValidations
      move(league, :finals, by)
    end

    def finish(league, by:)
      refuse("not_closed") unless league.closed?
      refuse("corrections_pending") if league.league_tables.correction_pending.exists?
      move(league, :finished, by)
    end

    private

    def refuse(key)
      raise NotAllowed, key
    end

    def move(league, state, by)
      from = league.state
      league.update!(state: state)
      Audit.record(:event_state_changed, actor: by, subject: league, event: league, from: from, to: state.to_s)
      league
    end
  end
end
