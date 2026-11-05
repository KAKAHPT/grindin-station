# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Exports
  class InvitationalTest < ActiveSupport::TestCase
    include ExportTournament

    setup do
      @year = Date.current.year
      @ana = users(:player_one)
      @bruno = users(:player_two)
      @gold = events(:finished_tournament)
      @plain = events(:standard_tournament)
    end

    test "header, the season's players with invitational points, ordered, with formula-safe names" do
      @bruno.update_columns(name: "=Bruno") # rubocop:disable Rails/SkipsModelValidations
      contribution(@ana, @gold, points: 10, invitational: 20)
      contribution(@ana, @plain, points: 5, invitational: 0)
      contribution(@bruno, @gold, points: 15.25, invitational: 30.5)
      contribution(users(:player_three), @gold, points: 3, invitational: 0)
      contribution(users(:player_four), @gold, points: 40, invitational: 80, season: @year - 1)

      rows = nil
      without_n_plus_one { rows = parse_export(Invitational.call(season: @year)) }

      assert_equal %w[standing name handle email invitational_points tier_events points events], rows.first
      assert_equal [%w[1 '=Bruno player-two player2@example.com 30.5 1 15.25 1],
                    ["2", "Player One", "player-one", "player1@example.com", "20", "1", "15", "2"]], rows.drop(1)
    end

    test "all seasons when season is nil; a guest has a blank handle and e-mail" do
      contribution(@ana, @gold, points: 10, invitational: 20, season: @year - 1)
      guest = Player.create!(guest_name: "Walk In", key: SecureRandom.hex(8))
      RankingContribution.create!(player: guest, event: @plain, season: @year, field: 4, format: "multiplayer",
                                  points: 2, invitational_points: 2)

      rows = parse_export(Invitational.call(season: nil)).drop(1)

      assert_equal [["1", "Player One", "player-one", "player1@example.com", "20", "1", "10", "1"],
                    ["2", "Walk In", nil, nil, "2", "1", "2", "1"]], rows
    end

    private

    def contribution(user, event, points:, invitational:, season: @year)
      RankingContribution.create!(player: user.player, event: event, season: season, field: 4, format: "multiplayer",
                                  points: points, invitational_points: invitational)
    end
  end
end
