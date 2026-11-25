# frozen_string_literal: true

module Leagues
  module Tables
    # A player who joined a waiting table leaves it. The opener closes the table instead (Close).
    class Leave
      def self.call(table:, participant:)
        LeagueTable.transaction do
          table.lock!
          raise NotAllowed, "not_waiting" unless table.waiting?
          raise NotAllowed, "opener_closes" if table.opener_id == participant.id

          seat = table.seats.find_by(event_participant_id: participant.id)
          raise NotAllowed, "not_member" unless seat

          seat.destroy!
          table.touch # rubocop:disable Rails/SkipsModelValidations -- pushes the list to the page
          table
        end
      end
    end
  end
end
