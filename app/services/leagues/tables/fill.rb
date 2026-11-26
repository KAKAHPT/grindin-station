# frozen_string_literal: true

module Leagues
  module Tables
    # The table has its four players: it becomes a game of the league. One LeagueGameRound with a single pod
    # is created, already started; the seat order is the fair one over the players' seats in this league.
    # Called by Join inside its transaction, with the table locked.
    class Fill
      def self.call(table:) = new(table).call

      def initialize(table)
        @table = table
        @league = table.league
      end

      def call
        @league.lock! # one game round number at a time
        pod = round.pods.create!(number: 1, size: League::TABLE_SIZE)
        seat(pod)
        @table.update!(state: "filled", pod: pod, filled_at: Time.current)
        Notify.participants(pod, kind: "league_table_full", subject: pod)
        pod
      end

      private

      def round
        LeagueGameRound.create!(event: @league, number: @league.rounds.maximum(:number).to_i + 1,
                                is_play_round: true, published: true, started_at: Time.current)
      end

      def seat(pod)
        players = @table.participants.to_a
        counts = SeatCounts.for(@league, players.map(&:id))
        assigner = Tournaments::SeatAssigner.new(participants: players, seat_counts: players.index_with do |p|
          counts[p.id]
        end,
                                                 rng: Random.new)
        assigner.order.each.with_index(1) do |participant, position|
          pod.seatings.create!(event_participant: participant, order: position, assigned_by: "fair",
                               cost: assigner.cost)
        end
      end
    end
  end
end
