# frozen_string_literal: true

require "test_helper"

class ProfileSummaryTest < ActionView::TestCase
  test "a row without games: win rate is a dash, conversion 0%, no commanders" do
    render "profiles/summary", summary: Profiles::Summary.call([row])

    assert_select "[data-profile-summary]" do
      assert_select "[data-stat=events]", text: "1"
      assert_select "[data-stat=top_cuts]", text: "0"
      assert_select "[data-stat=win_rate]", text: "–"
      assert_select "[data-stat=conversion]", text: "0%"
      assert_select "[data-ach=wins]", text: "0"
      assert_select "[data-ach=top4]", text: "0"
      assert_select "[data-ach=cuts]", text: "0"
      assert_select "[data-commanders] li", text: "–"
    end
  end

  test "no rows: both rates are a dash" do
    render "profiles/summary", summary: Profiles::Summary.call([])

    assert_select "[data-stat=win_rate]", text: "–"
    assert_select "[data-stat=conversion]", text: "–"
  end

  test "commanders with count, share of the events and a grey bar" do
    rows = [row(commander: "Kinnan"), row(commander: "Kinnan"), row(commander: "Tymna // Thrasios"), row]

    render "profiles/summary", summary: Profiles::Summary.call(rows)

    assert_select "[data-commanders] li", 2
    assert_select "[data-commanders] li:first-child", text: /Kinnan\s*2 · 50%/
    assert_select "[data-commanders] li:first-child [style*=?]", "width: 50%"
    assert_select "[data-profile-summary] .text-accent", 0
  end

  private

  def row(commander: nil)
    Profiles::History::Row.new(event: nil, position: nil, participants: 4, wins: 0, losses: 0, draws: 0, seats: nil,
                               decklist_visible: false, decklist: nil, games: 0, made_cut: false, cut_size: nil,
                               commander: commander, organizer_name: "", format_line: "", season: nil,
                               round_seats: nil)
  end
end
