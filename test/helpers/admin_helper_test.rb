# frozen_string_literal: true

require "test_helper"

class AdminHelperTest < ActionView::TestCase
  test "sparkline draws one polyline point per value scaled to the box" do
    html = sparkline([0, 5, 10], width: 100, height: 20)

    assert_includes html, 'viewBox="0 0 100 20"'
    assert_includes html, 'points="0.0,20.0 50.0,10.0 100.0,0.0"'
    assert_includes html, 'stroke="currentColor"'
  end

  test "sparkline of all zeros is a flat line at the bottom" do
    assert_includes sparkline([0, 0]), 'points="0.0,28.0 120.0,28.0"'
  end
end
