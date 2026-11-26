# frozen_string_literal: true

module Leagues
  module Tables
    # An enrolled player takes a seat at a waiting table; the 4th seat fills it (Fill).
    class Join
      include Guard

      def self.call(table:, participant:) = new(table, participant).call

      def initialize(table, participant)
        @table = table
        @participant = participant
      end

      def call
        LeagueTable.transaction do
          @table.lock!
          check!
          @table.seats.create!(event_participant: @participant)
          Fill.call(table: @table) if @table.seats.count == League::TABLE_SIZE
          @table
        end
      end

      private

      def check!
        refuse("not_waiting") if !@table.waiting? || @table.overdue?
        refuse("full") if @table.seats.count >= League::TABLE_SIZE
        check_can_sit!(@table.league, @participant)
        check_opponents!(@table.league, @participant, @table)
      end
    end
  end
end
