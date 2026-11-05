# frozen_string_literal: true

require "test_helper"

module Rankings
  class EloTest < ActiveSupport::TestCase
    test "worked example: Ana 1500 wins a pod against 1600, 1500 and 1400 and ends near 1548" do
      elo = Elo.new(ratings: { ana: 1500, bia: 1600, rui: 1500, zé: 1400 })

      elo.play_pod([[:ana, :bia, 1], [:ana, :rui, 1], [:ana, :zé, 1],
                    [:bia, :rui, 0.5], [:bia, :zé, 0.5], [:rui, :zé, 0.5]])

      assert_in_delta 1548, elo.rating(:ana), 0.5
      assert_equal 3, elo.games(:ana)
      assert_equal 3, elo.wins(:ana)
      assert_in_delta 1548, elo.peak(:ana), 0.5
      assert_equal 0, elo.wins(:bia)
    end

    test "a drawn pod of equal ratings leaves everyone at 1500" do
      elo = Elo.new
      players = %i[a b c d]

      elo.play_pod(players.combination(2).map { |a, b| [a, b, 0.5] })

      players.each { |id| assert_in_delta 1500, elo.rating(id), 1e-9 }
      assert_equal 3, elo.games(:a)
    end

    test "expected score of 1500 against 1700 is about 0.24" do
      assert_in_delta 0.24, Elo.new.expected(1500, 1700), 0.005
    end

    test "play updates both players from their pre-duel ratings" do
      elo = Elo.new

      elo.play(:a, :b, 1)

      assert_in_delta 1516, elo.rating(:a), 1e-9
      assert_in_delta 1484, elo.rating(:b), 1e-9
      assert_in_delta 1500, elo.peak(:b), 1e-9
      assert_equal 1, elo.wins(:a)
      assert_equal 0, elo.wins(:b)
    end

    test "a player is provisional until 10 rated games" do
      elo = Elo.new
      9.times { elo.play(:a, :b, 0.5) }

      assert elo.provisional?(:a)
      assert elo.provisional?(:unknown)

      elo.play(:a, :b, 0.5)

      assert_not elo.provisional?(:a)
    end

    test "to_h lists rating, peak, games and wins per player" do
      elo = Elo.new
      elo.play(:a, :b, 1)

      assert_equal({ rating: 1516.0, peak: 1516.0, games: 1, wins: 1 }, elo.to_h[:a])
      assert_equal %i[a b], elo.to_h.keys
    end
  end
end
