# frozen_string_literal: true

require "test_helper"

module Rankings
  class PointsTest < ActiveSupport::TestCase
    test "a 16-player winner with 3 wins and a draw scores 30" do
      assert_equal BigDecimal("30"), total(field: 16, wins: 3, draws: 1, made_cut: true, top4: true, won: true)
    end

    test "the same winner at 80 players scores 60" do
      assert_equal BigDecimal("60"), total(field: 80, wins: 3, draws: 1, made_cut: true, top4: true, won: true)
    end

    test "2-1-1 and made the cut only, at 16 players, scores 12" do
      assert_equal BigDecimal("12"), total(field: 16, wins: 2, draws: 1, made_cut: true)
    end

    test "a league player with 4 wins at 20 players scores 15, with no bonuses" do
      assert_equal BigDecimal("15"), total(field: 20, wins: 4, made_cut: true, top4: true, won: true, league: true)
    end

    test "a bye counts 1" do
      assert_equal 1, Points.games(wins: 0, draws: 0, byes: 1)
      assert_equal BigDecimal("1"), total(field: 8, byes: 1)
    end

    test "bonuses are cumulative" do
      flags = [[false, false, false], [true, false, false], [true, true, false], [true, true, true]]

      assert_equal([0, 5, 10, 20], flags.map { |cut, top4, won| Points.bonuses(made_cut: cut, top4: top4, won: won) })
    end

    test "field factor boundaries" do
      assert_equal([1, 1, 1.25, 1.25, 1.5, 1.5, 2], [1, 16, 17, 32, 33, 64, 65].map { |field| Points.factor(field) })
    end

    test "the total is rounded to 2 decimals" do
      assert_equal BigDecimal("1.25"), total(field: 17, draws: 1)
      assert_equal 2, total(field: 17, draws: 1).scale
    end

    private

    def total(field:, wins: 0, draws: 0, byes: 0, made_cut: false, top4: false, won: false, league: false) # rubocop:disable Metrics/ParameterLists
      Points.total(field: field, wins: wins, draws: draws, byes: byes, made_cut: made_cut, top4: top4, won: won,
                   league: league)
    end
  end
end
