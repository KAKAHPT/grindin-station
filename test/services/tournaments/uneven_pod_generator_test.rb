# frozen_string_literal: true

require "test_helper"

module Tournaments
  class UnevenPodGeneratorTest < ActiveSupport::TestCase
    # n => [sizes, byes], from the shape table (r = n % 4).
    POD_OF_THREE_SHAPES = {
      4 => [[4], 0], 5 => [[4], 1], 6 => [[3, 3], 0], 7 => [[4, 3], 0], 8 => [[4, 4], 0],
      9 => [[3, 3, 3], 0], 10 => [[4, 3, 3], 0], 11 => [[4, 4, 3], 0], 12 => [[4, 4, 4], 0],
      13 => [[4, 3, 3, 3], 0], 14 => [[4, 4, 3, 3], 0], 15 => [[4, 4, 4, 3], 0], 16 => [[4, 4, 4, 4], 0],
      17 => [[4, 4, 3, 3, 3], 0], 18 => [[4, 4, 4, 3, 3], 0], 19 => [[4, 4, 4, 4, 3], 0],
      20 => [[4, 4, 4, 4, 4], 0]
    }.freeze

    BYE_SHAPES = {
      4 => [[4], 0], 5 => [[4], 1], 6 => [[4], 2], 7 => [[4, 3], 0], 8 => [[4, 4], 0],
      9 => [[4, 4], 1], 10 => [[4, 4], 2], 11 => [[4, 4, 3], 0], 12 => [[4, 4, 4], 0],
      13 => [[4, 4, 4], 1], 14 => [[4, 4, 4], 2], 15 => [[4, 4, 4, 3], 0], 16 => [[4, 4, 4, 4], 0],
      17 => [[4, 4, 4, 4], 1], 18 => [[4, 4, 4, 4], 2], 19 => [[4, 4, 4, 4, 3], 0],
      20 => [[4, 4, 4, 4, 4], 0]
    }.freeze

    test "pods_of_three shapes for 4..20 players" do
      POD_OF_THREE_SHAPES.each do |n, (sizes, byes)|
        assert_equal({ sizes: sizes, byes: byes }, UnevenPodGenerator.shape(n, "pods_of_three"), "n = #{n}")
      end
    end

    test "byes shapes for 4..20 players" do
      BYE_SHAPES.each do |n, (sizes, byes)|
        assert_equal({ sizes: sizes, byes: byes }, UnevenPodGenerator.shape(n, "byes"), "n = #{n}")
      end
    end

    test "5 players: one pod of 4 and a bye in both modes, never a pod of 5" do
      assert_equal({ sizes: [4], byes: 1 }, UnevenPodGenerator.shape(5, "pods_of_three"))
      assert_equal({ sizes: [4], byes: 1 }, UnevenPodGenerator.shape(5, "byes"))
    end

    test "fewer than 4 players: one pod of everyone in both modes, no error" do
      (1..3).each do |n|
        Event::UNEVEN_FIELDS.each do |mode|
          assert_equal({ sizes: [n], byes: 0 }, UnevenPodGenerator.shape(n, mode), "n = #{n}, #{mode}")
        end
      end
    end
  end
end
