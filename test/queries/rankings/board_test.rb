# frozen_string_literal: true

require "test_helper"
require_relative "../../support/rankings_fixture"

module Rankings
  # Players in PT/ES, two organizers, three play pools, two teams, two seasons; contributions from Rankings::Rebuild.
  # This year: Ana wins two pods (cEDH PT), Carla beats Diogo at Legacy (Lisboa cEDH); last year: Bruno wins one pod,
  # Diogo beats Carla at Modern.
  class BoardTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    include RankingsFixture

    setup { build_rankings_world }

    test "defaults to the current year; points rows ordered by points" do
      board = Board.new({})

      assert_equal @this_year, board.filters[:season]
      assert_equal [@this_year, @last_year], board.seasons
      rows = board.points
      assert_equal(%w[Ana Carla], rows.first(2).map { |row| row.player.name.split.first })
      assert_equal [BigDecimal("26"), BigDecimal("13")], rows.first(2).map(&:points)
      ana = rows.first
      assert_equal [2, 2, 0, 0], [ana.events, ana.wins, ana.top_cuts, ana.conversion]
      assert_equal 1, ana.best
      assert_equal @ana, ana.user
      assert_equal 4, rows.size
    end

    test "the current year is the default and listed even before it has data" do
      travel_to Time.zone.local(@this_year + 1, 2, 1) do
        board = Board.new({})

        assert_equal @this_year + 1, board.filters[:season]
        assert_equal [@this_year + 1, @this_year, @last_year], board.seasons
        assert_empty board.points
        assert_equal @this_year, Board.new({ season: @this_year.to_s }).filters[:season]
      end
    end

    test "a player entered twice in an event does not multiply the points row" do
      before = Board.new({}).points.find { |row| row.user == @ana }
      entry = EventParticipant.where(player: @ana.player).order(:created_at).first
      # Validations (and the unique index, when present) refuse this now; older data may still hold such duplicates.
      # The index is dropped inside the test transaction, which rolls the DDL back.
      index = "index_event_participants_on_event_id_and_player_id"
      connection = EventParticipant.connection
      connection.remove_index(:event_participants, name: index) if connection.index_name_exists?(:event_participants,
                                                                                                 index)
      entry.event.event_participants.new(player: @ana.player, accepted_terms: true,
                                         final_position: 3).save!(validate: false)

      after = Board.new({}).points.find { |row| row.user == @ana }

      assert_equal before.to_h.except(:player, :user), after.to_h.except(:player, :user)
    end

    test "option lists" do
      board = Board.new({})

      assert_equal %w[ES PT], board.countries
      assert_equal [["Lisboa cEDH", "lisboa-cedh"], ["Tournament Organizer", "organizer-user"]], board.organizers
      assert_equal ["Madrid Mana", "Porto Grinders"], board.teams
    end

    test "each filter narrows the points rows" do
      {
        { season: @last_year.to_s } => %w[Bruno],
        { season: "all" } => %w[Ana Bruno Carla],
        { country: "ES" } => %w[Carla Diogo],
        { organizer: "lisboa-cedh" } => %w[Carla Diogo],
        { play: "legacy" } => %w[Carla Diogo],
        { play: "multiplayer" } => %w[Ana Bruno Carla Diogo],
        { team: "Porto Grinders" } => %w[Ana Bruno],
        { q: "carl" } => %w[Carla]
      }.each do |params, names|
        rows = Board.new(params).points
        assert_equal names, rows.map { |row| row.player.name.split.first }.first(names.size), params.inspect
        assert_equal names.size, rows.size, params.inspect unless params.key?(:season)
      end
    end

    test "unknown values are ignored" do
      board = Board.new({ season: "1999", country: "XX", organizer: "nobody", play: "one_v_one", team: "Nope",
                          q: " " })

      expected = { season: @this_year, country: nil, organizer: nil, event_organizer_id: nil, play: nil, team: nil,
                   q: nil }
      assert_equal expected, board.filters
      assert_equal 4, board.points.size
    end

    test "the organizer handle becomes the organizer id" do
      board = Board.new({ organizer: "lisboa-cedh" })

      assert_equal @lisboa.id, board.filters[:event_organizer_id]
    end

    test "elo rows keep the season rating whatever the country" do
      all = Board.new({}, tab: "elo").elo.index_by(&:player)
      spain = Board.new({ country: "ES" }, tab: "elo").elo

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

      row = Board.new({}, tab: "elo").elo.find { |r| r.player == lonely.player }

      assert_equal [1500, 0, 0, nil, true], [row.rating, row.change, row.games, row.win_pct, row.provisional]
    end

    test "points: a play narrows the contributions to that pool" do
      assert_empty Board.new({ play: "modern" }).points
      rows = Board.new({ play: "modern", season: "all" }).points

      assert_equal(%w[Diogo Carla], rows.map { |row| row.player.name.split.first })
      assert_equal [1, 0], rows.map(&:wins)
    end

    test "the leaderboard always shows one pool: multiplayer by default, unknown plays ignored" do
      assert_nil Board.new({}).filters[:play]
      assert_equal "multiplayer", Board.new({}, tab: "elo").filters[:play]
      assert_equal "multiplayer", Board.new({ play: "chess" }, tab: "elo").filters[:play]

      carla = Board.new({}, tab: "elo").elo.find { |row| row.user == @carla }

      assert_operator carla.rating, :<, 1500 # two pods lost to Ana
      assert_equal 2, carla.games
    end

    test "each play pool has its own ratings" do
      legacy = Board.new({ play: "legacy" }, tab: "elo").elo
      modern = Board.new({ play: "modern", season: "all" }, tab: "elo").elo

      assert_equal([[@carla, 1516, 1], [@diogo, 1484, 1]], legacy.map { |row| [row.user, row.rating, row.games] })
      assert_equal([[@diogo, 1516, 1], [@carla, 1484, 1]], modern.map { |row| [row.user, row.rating, row.games] })
      assert_empty Board.new({ play: "modern" }, tab: "elo").elo
    end

    test "the leaderboard summary counts the listed rows" do
      board = Board.new({ play: "legacy" }, tab: "elo")

      assert_equal board.elo.size, board.summary[:players]
      assert_equal({ players: 2, events: 1, organizers: 1 }, board.summary.except(:updated_at))
    end

    test "teams: the five best contributions count" do
      board = Board.new({ season: "all" })
      porto = board.teams_board.find { |row| row.team == "Porto Grinders" }

      # Ana 26 + 2 wins × 30 = 86; Bruno 13 + 30 = 43.
      assert_equal BigDecimal("129"), porto.points
      assert_equal [2, 6, 3, 0], [porto.players, porto.events, porto.wins, porto.top_cuts]
    end

    test "teams with six players drop the sixth" do
      event = events(:finished_tournament)
      users = (1..6).map { |i| new_user("Six #{i}", team: "Six Pack") }
      users.each_with_index do |user, i|
        RankingContribution.create!(player: user.player, event: event, season: @this_year, team: "Six Pack", field: 6,
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
                   Board.new({ organizer: "lisboa-cedh" }).summary.except(:updated_at))
    end
  end
end
