# frozen_string_literal: true

require "test_helper"

module Tournaments
  class SeatAssignerTest < ActiveSupport::TestCase
    A = "a"
    B = "b"
    C = "c"
    D = "d"
    E = "e"

    def counts(history) = history.transform_values { |arr| (1..5).zip(arr + ([0] * (5 - arr.size))).to_h }

    test "seat 1 goes to the player who has had it least" do
      sc = counts(A => [1, 0, 0, 0], B => [0, 1, 0, 0], C => [1, 0, 1, 0], D => [2, 0, 0, 0])
      order = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(1)).order
      assert_equal B, order.first
    end

    test "among seat-1 candidates the cheapest full order wins" do
      sc = counts(A => [0, 2, 0, 0], B => [0, 0, 2, 0], C => [1, 0, 0, 2], D => [1, 1, 1, 0])
      assigner = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(1))
      assert_includes [A, B], assigner.order.first
      assert_equal D, assigner.order.last, "D is the only one who never sat 4th"
      expected = assigner.order.each_with_index.sum { |p, i| Tournaments::SeatAssigner::WEIGHTS[i + 1] * (sc[p][i + 1]**2) }
      assert_equal expected, assigner.cost
    end

    test "ties are decided by the rng, reproducibly" do
      sc = counts(A => [], B => [], C => [], D => [])
      o1 = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(42)).order
      o2 = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(42)).order
      o3 = Tournaments::SeatAssigner.new(participants: [A, B, C, D], seat_counts: sc, rng: Random.new(7)).order
      assert_equal o1, o2
      assert_not_equal o1, o3
    end

    test "handles pods of 3 and 5" do
      sc = counts(A => [], B => [], C => [], D => [], E => [0, 0, 0, 0, 3])
      assert_equal 3,
                   Tournaments::SeatAssigner.new(participants: [A, B, C], seat_counts: sc,
                                                 rng: Random.new(1)).order.size
      five = Tournaments::SeatAssigner.new(participants: [A, B, C, D, E], seat_counts: sc, rng: Random.new(1)).order
      assert_equal 5, five.size
      assert_not_equal E, five.last
    end

    test "the seat-1 hard rule beats a cheaper order" do
      sc = counts(A => [0, 0, 0], B => [1, 5, 5], C => [1, 0, 0])
      assert_equal A,
                   Tournaments::SeatAssigner.new(participants: [A, B, C], seat_counts: sc,
                                                 rng: Random.new(1)).order.first
    end
  end
end
