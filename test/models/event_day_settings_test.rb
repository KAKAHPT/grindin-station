# frozen_string_literal: true

require "test_helper"

class EventDaySettingsTest < ActiveSupport::TestCase
  test "defaults" do
    t = Tournament.new
    assert_equal [true, "none", 5, false, false, "highest_seed_advances"],
                 [t.self_report_enabled, t.result_confirmation, t.confirmation_timeout_minutes,
                  t.waitlist_enabled, t.show_commanders_in_standings, t.top_cut_timeout_rule]
  end

  test "confirmation can change mid-tournament" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    assert t.update(result_confirmation: "all")
    assert_not t.update(result_confirmation: "two")
  end
end
