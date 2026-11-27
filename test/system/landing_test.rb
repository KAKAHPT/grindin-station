# frozen_string_literal: true

require "application_system_test_case"

class LandingTest < ApplicationSystemTestCase
  test "the landing renders with Why it is fair, joins the waiting list in place and logs no console error" do
    page.driver.browser.logs.get(:browser) # drain what earlier tests in this browser logged
    visit root_path

    assert_selector "h1", text: "The grind never stops."
    within(".lp-why") { assert_text "Seats are weighted, not drawn" }

    within("[data-waitlist]") do
      fill_in "waitlist_signup_name", with: "Ana"
      fill_in "waitlist_signup_email", with: "ana@example.com"
      click_on "Join"
      assert_text "You're on the list"
    end
    assert_current_path root_path
    assert WaitlistSignup.exists?(email: "ana@example.com")

    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" }.map(&:message)
    assert_empty errors, "console errors on the landing"
  end

  test "three featured events move: the row is in motion and the ticket at the front opens its details" do
    organizer = event_organizers(:standard_organizer)
    3.times do |index|
      event = Tournament.create!(name: "Star #{index}", event_organizer: organizer, state: :draft,
                                 start_time: (index + 1).days.from_now, end_time: (index + 2).days.from_now)
      event.update_columns(state: Tournament.states[:registration_open], featured: true) # rubocop:disable Rails/SkipsModelValidations
    end
    visit root_path

    assert_selector "[data-featured] .lp-rail.lp-flow [data-featured-event]", minimum: 6, visible: :all
    open = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("[data-ft-more]")].filter((el) => getComputedStyle(el).opacity > 0.9).length
    JS
    assert_equal 1, open, "exactly the front ticket shows its details"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end

  test "a single featured event stays at the front, lifted, floating and with its details open" do
    event = Tournament.create!(name: "Lone Star", event_organizer: event_organizers(:standard_organizer), state: :draft,
                               start_time: 1.day.from_now, end_time: 2.days.from_now)
    event.update_columns(state: Tournament.states[:registration_open], featured: true) # rubocop:disable Rails/SkipsModelValidations
    visit root_path

    assert_selector "[data-featured] .lp-rail.lp-flow [data-featured-event]", count: 1
    front = page.evaluate_script(<<~JS)
      (() => {
        const ticket = document.querySelector("[data-featured-event]");
        const box = ticket.getBoundingClientRect();
        const row = ticket.parentElement.getBoundingClientRect();
        const off = Math.abs(box.left + box.width / 2 - (row.left + row.width / 2));
        return { centred: off < 4, floating: ticket.getAnimations().length === 1, open: getComputedStyle(ticket.querySelector("[data-ft-more]")).opacity > 0.9 };
      })()
    JS
    assert front["centred"], "the ticket sits in the middle of the row"
    assert front["floating"], "it floats"
    assert front["open"], "its details are open"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end
end
