# frozen_string_literal: true

module Leagues
  module Tables
    # The organizer answers a cancellation request. Approved: the game is removed (round, pod, seats and any
    # result), counts for nothing and its players are free. Refused: the table stays and must be reported.
    class DecideCancel
      def self.call(table:, by:, approve:) = new(table, by, approve).call

      def initialize(table, by, approve)
        @table = table
        @by = by
        @approve = approve
      end

      def call
        LeagueTable.transaction do
          @table.lock!
          raise NotAllowed, "nothing_pending" unless @table.cancel_pending?

          users = @table.pod.users.pluck(:id)
          @approve ? approve : @table.update!(cancel_state: "refused", **decided)
          Audit.record(:league_table_cancel_decided, actor: @by, subject: @table, event: @table.league,
                                                     approved: @approve, reason: @table.cancel_reason)
          Notify.create_for(users, kind: "league_cancel_#{@approve ? 'approved' : 'refused'}", subject: @table.league)
          @table
        end
      end

      private

      def decided = { cancel_decided_by: @by, cancel_decided_at: Time.current }

      def approve
        league = @table.league
        round = @table.pod.round
        @table.release_seats!
        @table.update!(state: "cancelled", cancel_state: "approved", pod: nil, **decided)
        round.destroy!
        Scoring::PointWager.new(league).recalculate_all!
        Lifecycle.settle_closing(league)
      end
    end
  end
end
