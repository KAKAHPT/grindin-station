# frozen_string_literal: true

require "test_helper"
require_relative "../../support/rankings_fixture"

module Rankings
  # Players in PT/ES, two organizers, both formats, two teams, two seasons; contributions from Rankings::Rebuild.
  # 2026: Ana wins two pods (cEDH PT), Carla beats Diogo 1v1 (Lisboa cEDH); 2025: Bruno wins one pod.
  class BoardTest < ActiveSupport::TestCase
    include RankingsFixture

    setup { build_rankings_world }

    test "defaults to the latest season with data; points rows ordered by points" do
      board = Board.new({})

      assert_equal 2026, board.filters[:season]
      assert_equal [2026, 2025], board.seasons
      rows = board.points
      assert_equal(%w[Ana Carla], rows.first(2).map { |row| row.player.name.split.first })
      assert_equal [BigDecimal("26"), BigDecimal("13")], rows.first(2).map(&:points)
      ana = rows.first
      assert_equal [2, 2, 0, 0], [ana.events, ana.wins, ana.top_cuts, ana.conversion]
      assert_equal 1, ana.best
      assert_equal @ana, ana.user
      assert_equal 4, rows.size
    end

    test "option lists" do
      board = Board.new({})

      assert_equal %w[ES PT], board.countries
      assert_equal [["Lisboa cEDH", "lisboa-cedh"], ["Tournament Organizer", "organizer-user"]], board.organizers
      assert_equal ["Madrid Mana", "Porto Grinders"], board.teams
    end

    test "each filter narrows the points rows" do
      {
        { season: "2025" } => %w[Bruno],
        { season: "all" } => %w[Ana Bruno Carla],
        { country: "ES" } => %w[Carla Diogo],
        { organizer: "lisboa-cedh" } => %w[Carla Diogo],
        { format: "one_v_one" } => %w[Carla Diogo],
        { team: "Porto Grinders" } => %w[Ana Bruno],
        { q: "carl" } => %w[Carla]
      }.each do |params, names|
        rows = Board.new(params).points
        assert_equal names, rows.map { |row| row.player.name.split.first }.first(names.size), params.inspect
        assert_equal names.size, rows.size, params.inspect unless params.key?(:season)
      end
    end

    test "unknown values are ignored" do
      board = Board.new(season: "1999", country: "XX", organizer: "nobody", format: "chess", team: "Nope", q: " ")

      expected = { season: 2026, country: nil, organizer: nil, event_organizer_id: nil, format: nil, team: nil, q: nil }
      assert_equal expected, board.filters
      assert_equal 4, board.points.size
    end

    test "the organizer handle becomes the organizer id" do
      board = Board.new(organizer: "lisboa-cedh")

      assert_equal @lisboa.id, board.filters[:event_organizer_id]
    end

    test "elo rows keep the season rating whatever the country" do
      all = Board.new({}).elo.index_by(&:player)
      spain = Board.new(country: "ES").elo

      assert_equal 4, all.size
      assert_equal [@carla.player, @diogo.player].to_set, spain.to_set(&:player)
      spain.each do |row|
        assert_equal all.fetch(row.player).rating, row.rating
        assert row.provisional
      end
      assert_operator all.fetch(@ana.player).rating, :>, 1500
      assert_equal all.values.map(&:rating).sort.reverse, all.values.map(&:rating)
    end

    test "a player with contributions but no rated pod shows 1500, no change, provisional" do
      lonely = new_user("Eva Sola", country: "PT")
      event = TournamentBuilder.build(players: 3, organizer: @standard, state: :finished)
      event.event_participants.first.update_columns(player_id: lonely.player.id) # rubocop:disable Rails/SkipsModelValidations
      Rebuild.call

      row = Board.new({}).elo.find { |r| r.player == lonely.player }

      assert_equal [1500, 0, 0, nil, true], [row.rating, row.change, row.games, row.win_pct, row.provisional]
    end

    test "teams: the five best contributions count" do
      board = Board.new(season: "all")
      porto = board.teams_board.find { |row| row.team == "Porto Grinders" }

      # Ana 26 + 2 wins × 30 = 86; Bruno 13 + 30 = 43.
      assert_equal BigDecimal("129"), porto.points
      assert_equal [2, 6, 3, 0], [porto.players, porto.events, porto.wins, porto.top_cuts]
    end

    test "teams with six players drop the sixth" do
      event = events(:finished_tournament)
      users = (1..6).map { |i| new_user("Six #{i}", team: "Six Pack") }
      users.each_with_index do |user, i|
        RankingContribution.create!(player: user.player, event: event, season: 2026, team: "Six Pack", field: 6,
                                    format: "multiplayer", points: (i + 1) * 10, made_cut: i == 5, won: i == 4)
      end

      row = Board.new({}).teams_board.find { |r| r.team == "Six Pack" }

      # 60 + 15 (cut), 50 + 30 (won), 40, 30, 20; the 10 is dropped.
      assert_equal BigDecimal("245"), row.points
      assert_equal [6, 1, 1], [row.players, row.wins, row.top_cuts]
      assert_equal 1500, row.avg_rating
    end

    test "summary counts the matching players, events and organizers" do
      summary = Board.new({}).summary

      assert_equal({ players: 4, events: 3, organizers: 2 }, summary.except(:updated_at))
      assert_in_delta Rankings.last_rebuilt_at, summary[:updated_at], 0.001
      assert_equal({ players: 2, events: 1, organizers: 1 },
                   Board.new(organizer: "lisboa-cedh").summary.except(:updated_at))
    end
  end
end
