# frozen_string_literal: true

module Leagues
  module Tables
    # The checks shared by opening and joining a table. Run inside a transaction: the participant's row is
    # locked, so two requests of the same player cannot both pass.
    module Guard
      private

      def refuse(key)
        raise NotAllowed, key
      end

      def check_can_sit!(league, participant)
        refuse("closed") unless league.tables_open?
        refuse("not_enrolled") unless participant&.event_id == league.id && participant.enrolled?
        participant.lock!
        refuse("busy") if LeagueTableSeat.active.exists?(event_participant_id: participant.id)
        refuse("limit_week") if over_week_limit?(league, participant)
      end

      def over_week_limit?(league, participant)
        limit = league.max_games_per_week
        limit.present? && games_of(league, participant).where(filled_at: 7.days.ago..).count >= limit
      end

      # Joining would give this player one game too many against someone already at the table.
      def check_opponents!(league, participant, table)
        limit = league.max_games_vs_same_opponent
        return if limit.blank?

        mine = games_of(league, participant).select(:id)
        times = LeagueTableSeat.where(league_table_id: mine,
                                      event_participant_id: table.seats.map(&:event_participant_id))
          .group(:event_participant_id).count
        refuse("limit_opponent") if times.values.any? { |count| count >= limit }
      end

      # The filled (played or in play) tables of the league this player sat at.
      def games_of(league, participant)
        league.league_tables.filled
          .where(id: LeagueTableSeat.where(event_participant_id: participant.id).select(:league_table_id))
      end
    end
  end
end
