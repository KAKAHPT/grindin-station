# frozen_string_literal: true

module Leagues
  module Tables
    # Waiting tables opened more than League::TABLE_WAIT ago close by themselves. Returns how many.
    class Expire
      def self.call(now: Time.current)
        LeagueTable.waiting.where(created_at: ..(now - League::TABLE_WAIT)).find_each.count do |table|
          LeagueTable.transaction do
            table.lock!
            next false unless table.waiting?

            table.release_seats!
            table.update!(state: "expired")
            Turbo::StreamsChannel.broadcast_refresh_later_to(table.league, :tables)
          end
        end
      end
    end
  end
end
