# frozen_string_literal: true

module Leagues
  module Tables
    # An enrolled player opens a table and takes its first seat.
    class Open
      include Guard

      def self.call(league:, participant:) = new(league, participant).call

      def initialize(league, participant)
        @league = league
        @participant = participant
      end

      def call
        LeagueTable.transaction do
          check_can_sit!(@league, @participant)
          table = @league.league_tables.create!(opener: @participant)
          table.seats.create!(event_participant: @participant)
          table
        end
      end
    end
  end
end
