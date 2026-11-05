# frozen_string_literal: true

module Admin
  # The invitational leaderboard (spec M13 D16): per player, the invitational points of a season's contributions
  # (season nil = every season), players with none left out, highest first. Shared by /admin/invitational and its
  # CSV export.
  module Invitational
    Row = Data.define(:player, :invitational_points, :tier_events, :points, :events)

    # Seasons with contributions, newest first.
    def self.seasons = RankingContribution.distinct.pluck(:season).sort.reverse

    # player_id, then the Row figures in order; tier events are the contributions with invitational points.
    COLUMNS = [:player_id, Arel.sql("SUM(invitational_points)"),
               Arel.sql("COUNT(*) FILTER (WHERE invitational_points > 0)"), Arel.sql("SUM(points)"),
               Arel.sql("COUNT(*)")].freeze
    ORDER = Arel.sql("SUM(invitational_points) DESC, SUM(points) DESC, player_id")

    def self.rows(season:)
      scope = season ? RankingContribution.where(season: season) : RankingContribution.all
      totals = scope.group(:player_id).having("SUM(invitational_points) > 0").order(ORDER).pluck(*COLUMNS)
      players = Player.where(id: totals.map(&:first)).includes(:user).index_by(&:id)
      totals.map { |id, *figures| Row.new(players.fetch(id), *figures) }
    end
  end
end
