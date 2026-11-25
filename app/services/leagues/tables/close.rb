# frozen_string_literal: true

module Leagues
  module Tables
    # The opener closes their waiting table: everyone in it is free again.
    class Close
      def self.call(table:, participant:)
        LeagueTable.transaction do
          table.lock!
          raise NotAllowed, "not_waiting" unless table.waiting?
          raise NotAllowed, "not_opener" unless table.opener_id == participant.id

          table.release_seats!
          table.update!(state: "closed")
          table
        end
      end
    end
  end
end
