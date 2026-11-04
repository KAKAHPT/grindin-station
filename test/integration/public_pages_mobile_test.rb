# frozen_string_literal: true

require "test_helper"

# Structural checks that the public pages fit a 375 px phone: no fixed widths past the viewport and
# every table scrolls inside its own overflow box (the device check itself is the Lighthouse task's).
class PublicPagesMobileTest < ActionDispatch::IntegrationTest
  VIEWPORT = 375

  setup do
    @tournament = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(swiss_rounds_count: 3, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    @tournament.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
  end

  test "the public pages have no element wider than a phone" do
    [play_event_path(@tournament.slug), play_pairings_path(@tournament.slug),
     play_standings_path(@tournament.slug)].each do |path|
      get path

      assert_response :success
      assert_select "meta[name=viewport][content*='width=device-width']"
      assert_no_wide_inline_widths(path)
      assert_no_wide_arbitrary_widths(path)
      css_select("table").each do |table|
        assert table.ancestors.any? { |node| node["class"].to_s.split.include?("overflow-x-auto") },
               "#{path}: a table is not inside an overflow-x-auto box"
      end
    end
  end

  test "the pairings cards are one column on phones and widen from sm" do
    get play_pairings_path(@tournament.slug)

    assert_select "[data-pairings].grid.grid-cols-1.sm\\:grid-cols-2.lg\\:grid-cols-3"
  end

  private

  def assert_no_wide_inline_widths(path)
    css_select("[style]").each do |node|
      node["style"].scan(/(?:min-)?width:\s*(\d+)px/).flatten.map(&:to_i).each do |width|
        assert_operator width, :<=, VIEWPORT, "#{path}: inline width #{width}px"
      end
    end
  end

  # Tailwind arbitrary widths such as w-[480px] or min-w-[30rem] without a breakpoint prefix.
  def assert_no_wide_arbitrary_widths(path)
    css_select("[class]").each do |node|
      node["class"].split.grep(/\A(?:min-)?w-\[(\d+)(px|rem)\]\z/).each do |klass|
        value, unit = klass.match(/\[(\d+)(px|rem)\]/).captures
        px = unit == "rem" ? value.to_i * 16 : value.to_i
        assert_operator px, :<=, VIEWPORT, "#{path}: #{klass}"
      end
    end
  end
end
