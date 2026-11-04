# frozen_string_literal: true

require "test_helper"

module Tournaments
  class TopCutTest < ActiveSupport::TestCase
    test "stages per size" do
      assert_equal [{ byes: 0, pods: 1 }], Tournaments::TopCut.for(4).stages
      assert_equal [{ byes: 2, pods: 2 }, { byes: 0, pods: 1 }], Tournaments::TopCut.for(10).stages
      assert_equal [{ byes: 1, pods: 3 }, { byes: 0, pods: 1 }], Tournaments::TopCut.for(13).stages
      assert_equal [{ byes: 0, pods: 4 }, { byes: 0, pods: 1 }], Tournaments::TopCut.for(16).stages
      assert_equal [{ byes: 8, pods: 8 }, { byes: 0, pods: 4 }, { byes: 0, pods: 1 }], Tournaments::TopCut.for(40).stages
    end

    test "unknown size raises and validity needs enough players" do
      assert_raises(ArgumentError) { Tournaments::TopCut.for(8) }
      assert Tournaments::TopCut.for(16).valid_for?(16)
      assert_not Tournaments::TopCut.for(16).valid_for?(12)
    end

    test "1v1 sizes, rounds and stages" do
      assert_equal [2, 4, 8, 16, 32], Tournaments::TopCut.sizes_for("one_v_one")
      assert_equal [4, 10, 13, 16, 40], Tournaments::TopCut.sizes_for("multiplayer")
      assert_equal({ 2 => 1, 4 => 2, 8 => 3, 16 => 4, 32 => 5 },
                   [2, 4, 8, 16, 32].index_with { |s| Tournaments::TopCut.rounds_for(s, format: "one_v_one") })
      assert_equal [{ byes: 0, pods: 4 }, { byes: 0, pods: 2 }, { byes: 0, pods: 1 }],
                   Tournaments::TopCut.for(8, format: "one_v_one").stages
      assert_raises(ArgumentError) { Tournaments::TopCut.for(10, format: "one_v_one") }
      assert Tournaments::TopCut.valid_for?(8, format: "one_v_one", players: 8)
      assert_not Tournaments::TopCut.valid_for?(8, format: "one_v_one", players: 7)
      assert_not Tournaments::TopCut.valid_for?(10, format: "one_v_one", players: 20)
    end
  end
end
