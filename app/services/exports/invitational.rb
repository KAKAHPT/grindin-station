# frozen_string_literal: true

module Exports
  # The invitational leaderboard of a season (nil = all seasons) for /admin/invitational/export.csv.
  module Invitational
    HEADERS = %w[standing name handle email invitational_points tier_events points events].freeze

    def self.call(season:)
      rows = Admin::Invitational.rows(season: season).each.with_index(1).map { |row, standing| line(row, standing) }
      CsvFile.generate(HEADERS, rows)
    end

    def self.line(row, standing)
      user = row.player.user
      [standing, row.player.name, user&.handle, user&.email_address, number(row.invitational_points),
       row.tier_events, number(row.points), row.events]
    end

    # 20 rather than 20.0, 30.5 rather than 0.305e2.
    def self.number(value) = value.frac.zero? ? value.to_i : value.to_s("F")
  end
end
