# frozen_string_literal: true

require "application_system_test_case"

# The TV screen in a real browser: the tables take turns in blocks and a new result shows under the clock.
class ScreenTest < ApplicationSystemTestCase
  # Visible boxes of the screen that leave the window, and the clock when it leaves its card.
  OUTSIDE_THE_WINDOW = <<~JS
    (() => {
      const out = []
      const boxes = "[data-screen] aside, [data-screen] article, [data-screen-latest], [data-screen-pager]"
      document.querySelectorAll(boxes).forEach((box) => {
        if (box.closest("[hidden]")) return
        const r = box.getBoundingClientRect()
        if (r.left < -1 || r.top < -1 || r.right > innerWidth + 1 || r.bottom > innerHeight + 1) out.push(box.tagName)
      })
      const clock = document.querySelector("[data-screen-clock] span").getBoundingClientRect()
      const card = document.querySelector("[data-screen] aside").getBoundingClientRect()
      if (clock.right > card.right - 4 || clock.left < card.left) out.push("clock")
      return out
    })()
  JS

  setup do
    @tournament = TournamentBuilder.build(players: 104, organizer: event_organizers(:standard_organizer))
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: 37.minutes.ago)
  end

  test "26 tables come in three blocks that take turns; a reported table becomes the latest result" do
    travel_to(3.minutes.ago) { report(7, winner: 0) }
    travel_to(2.minutes.ago) { report(2, winner: nil) }
    report(4, winner: 2)
    page.driver.browser.manage.window.resize_to(1920, 1080)
    visit "#{play_screen_path(@tournament.slug)}?seconds=1"

    assert_selector "[data-screen-clock]", text: /\A\d\d:\d\d\z/
    assert_selector "[data-screen-pages-target=page]", count: 3, visible: :all
    assert_selector "article[data-pod-number='1']"
    assert_no_selector "article[data-pod-number='26']"
    assert_selector "[data-screen-latest]", text: /Table 4/i
    assert_selector "[data-screen-results] li", count: 2
    assert_selector "[data-screen-results] li:first-of-type", text: /Table 2\s+Draw/
    assert_selector "[data-screen-progress]", text: %r{3 / 26 TABLES FINISHED}i

    assert_selector "article[data-pod-number='26']", wait: 6
    assert_no_selector "article[data-pod-number='1']"
    assert_selector "[data-screen-pager]", text: /TABLES 19–26/i
  end

  test "the whole screen scales with the window: nothing leaves it and the clock stays inside its card" do
    @tournament.update_columns(round_minutes: 150) # rubocop:disable Rails/SkipsModelValidations
    @round.update!(started_at: 5.seconds.ago)

    [[1920, 1080], [800, 600], [2560, 900], [420, 800]].each do |width, height|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height,
                                                                            deviceScaleFactor: 1, mobile: false)
      visit play_screen_path(@tournament.slug)
      assert_selector "[data-screen-clock]", text: /\A149:\d\d\z/

      assert_equal [], outside_the_window, "#{width}x#{height}"
      assert_equal (width < height * 0.8).to_s, find("[data-screen]")["data-upright"], "#{width}x#{height}"
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def outside_the_window = page.evaluate_script(OUTSIDE_THE_WINDOW)

  def report(number, winner:)
    @round.pods.find_by!(number: number).seatings.order(:order).each_with_index do |seating, index|
      type =
        if winner.nil? then Draw
        elsif index == winner then Win
        else Loss
        end
      type.create!(round: @round, event_participant_id: seating.event_participant_id)
    end
  end
end
