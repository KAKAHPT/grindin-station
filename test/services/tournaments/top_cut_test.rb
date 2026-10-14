# frozen_string_literal: true

require "test_helper"

class Tournaments::TopCutTest < ActiveSupport::TestCase
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
end
