# frozen_string_literal: true

require "test_helper"

class RoundsHelperTest < ActionView::TestCase
  test "remaining time as mm:ss" do
    travel_to Time.zone.parse("2026-11-04 12:00:00") do
      assert_equal "40:00", clock_text(10.minutes.ago, 50 * 60)
    end
  end

  test "00:00 once time is up" do
    travel_to Time.zone.parse("2026-11-04 12:00:00") do
      assert_equal "00:00", clock_text(60.minutes.ago, 50 * 60)
    end
  end

  test "seconds that are not whole minutes" do
    travel_to Time.zone.parse("2026-11-04 12:00:00") do
      assert_equal "05:00", clock_text(30.seconds.ago, 330)
    end
  end

  test "a closed round shows how long it took as m:ss" do
    started = Time.zone.parse("2026-11-04 12:00:00")
    assert_equal "72:05", finished_clock_text(started, started + 72.minutes + 5.seconds)
    assert_equal "5:09", finished_clock_text(started, started + 5.minutes + 9.seconds)
  end

  test "an untimed round shows the elapsed time" do
    travel_to Time.zone.parse("2026-11-04 12:00:00") do
      assert_equal "01:30", clock_text(90.seconds.ago, nil)
    end
  end
end
