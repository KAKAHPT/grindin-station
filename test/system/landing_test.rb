# frozen_string_literal: true

require "application_system_test_case"

class LandingTest < ApplicationSystemTestCase
  test "the landing renders with Anne's seat board, joins the waiting list in place and logs no console error" do
    page.driver.browser.logs.get(:browser) # drain what earlier tests in this browser logged
    visit root_path

    assert_selector "h1", text: /The tournament software\s+with fair seats\./
    within("[data-seat-board]") { assert_text "Anne" }

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
end
