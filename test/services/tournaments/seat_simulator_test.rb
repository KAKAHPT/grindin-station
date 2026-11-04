# frozen_string_literal: true

require "test_helper"

module Tournaments
  class SeatSimulatorTest < ActiveSupport::TestCase
    # Regression levels of need-aware dealing (measured + 0.005 / − 0.02); the aspirational targets (<= 1 %, >= 99 %)
    # are in docs/superpowers/notes/2026-10-27-seat-simulation.md.
    test "never-first stays at or under 6.2 % over 4 rounds with 40 players" do
      rates =
        Array.new(50) do |i|
          Tournaments::SeatSimulator.new(players: 40, rounds: 4, rng: Random.new(i)).run.never_first_rate
        end
      assert_operator rates.sum / rates.size, :<=, 0.062
    end

    test "spread stays within one seat for at least 94.8 % of players over 5 rounds" do
      report = Tournaments::SeatSimulator.new(players: 64, rounds: 5, rng: Random.new(3)).run
      assert_operator report.max_spread_le1_rate, :>=, 0.948
    end

    test "the same rng seed produces the same report" do
      first = Tournaments::SeatSimulator.new(players: 37, rounds: 6, rng: Random.new(7)).run
      second = Tournaments::SeatSimulator.new(players: 37, rounds: 6, rng: Random.new(7)).run
      assert_equal first, second
    end

    test "random mode runs and reports for every player" do
      report = Tournaments::SeatSimulator.new(players: 16, rounds: 5, rng: Random.new(1), seating: :fair,
                                              mode: :random).run
      assert_equal 16, report.seat_counts.size
      assert_equal 5, report.seat_counts.values.sum { |counts| counts.values.sum } / 16
    end

    test "power mode is identical to swiss in the simulator" do
      swiss = Tournaments::SeatSimulator.new(players: 37, rounds: 5, rng: Random.new(9), mode: :swiss).run
      power = Tournaments::SeatSimulator.new(players: 37, rounds: 5, rng: Random.new(9), mode: :power).run
      assert_equal swiss, power
    end

    test "an unknown mode raises ArgumentError" do
      error = assert_raises(ArgumentError) { Tournaments::SeatSimulator.new(players: 16, rounds: 5, rng: Random.new(1), mode: :bubble) }
      assert_match(/unknown mode :bubble/, error.message)
    end
  end
end
