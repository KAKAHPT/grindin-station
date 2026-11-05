# frozen_string_literal: true

require "test_helper"

module Tournaments
  class ShortPodRepairTest < ActiveSupport::TestCase
    NEVER = ->(_a, _b) { false }

    test "a repeating player in a pod of 3 swaps into a pod of 4" do
      small, large = pods
      left = repair(small, large, short: { 7 => 1 }).repair!
      assert_equal 0, left
      assert(large.any? { |pod| pod.include?(7) })
      assert_equal 11, (small + large).flatten.uniq.size
    end

    test "no swap when it would add a rematch" do
      small, large = pods
      partners = large.flatten.to_set
      met = ->(a, b) { (a == 7 && partners.include?(b)) || (b == 7 && partners.include?(a)) }
      left = repair(small, large, short: { 7 => 1 }, met: met).repair!
      assert_equal 1, left
      assert_equal [[7, 8, 9]], small
    end

    test "the points gap limits the swap" do
      points = ->(player) { player == 7 ? 3 : 0 }
      small, large = pods
      assert_equal 1, repair(small, large, short: { 7 => 1 }, points: points, gap: 0).repair!
      assert_equal [[7, 8, 9]], small

      assert_equal 0, repair(small, large, short: { 7 => 1 }, points: points, gap: Float::INFINITY).repair!
      assert_not_includes small.first, 7
    end

    test "one eligible partner goes to the lowest-ranked repeating player" do
      small = [[7, 8, 9]]
      large = [[1, 2, 3, 4]]
      left = repair(small, large, short: { 1 => 1, 2 => 1, 3 => 1, 8 => 1, 9 => 1 }).repair!
      assert_equal 1, left
      assert_equal [[7, 8, 4]], small
      assert_equal [[1, 2, 3, 9]], large
    end

    private

    def pods = [[[7, 8, 9]], [[1, 2, 3, 4], [5, 6, 10, 11]]]

    def repair(small, large, short:, **options)
      ShortPodRepair.new(small: small, large: large, short_count: ->(player) { short.fetch(player, 0) },
                         points: options.fetch(:points, ->(_) { 0 }), met: options.fetch(:met, NEVER),
                         max_point_gap: options.fetch(:gap, 0))
    end
  end
end
