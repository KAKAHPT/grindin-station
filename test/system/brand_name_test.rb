# frozen_string_literal: true

require "application_system_test_case"

# The site's name sits beside the mark in the top bar and leads home; it fits a phone without pushing the bar wider.
class BrandNameTest < ApplicationSystemTestCase
  test "the name shows beside the mark, links home and fits a phone" do
    visit events_path
    assert_selector ".topbar-brand [data-brand-name]", text: I18n.t("app.name"), visible: :visible

    window = page.driver.browser.manage.window
    size = window.size
    window.resize_to(375, 800)
    assert_selector ".topbar-brand [data-brand-name]", visible: :visible
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")

    find(".topbar-brand").click
    assert_current_path root_path, ignore_query: true
  ensure
    # The browser is shared by the tests that follow: left at phone width they would get the collapsed menu.
    window&.resize_to(size.width, size.height) if size
  end

  test "on a phone the viewer is their picture alone; tapping it opens the same menu as on a computer" do
    sign_in_as(users(:organizer_user))
    window = page.driver.browser.manage.window
    size = window.size
    window.resize_to(375, 800)
    visit events_path

    assert_selector "[data-user-menu] .topbar-me-trigger", visible: :visible
    assert_no_selector "[data-user-menu-panel] a", visible: :visible
    find("[data-user-menu] .topbar-me-trigger").click
    within "[data-user-menu-panel]" do
      [I18n.t("topbar.my_events"), I18n.t("accounts.nav"), I18n.t("topbar.logout"),
       I18n.t("topbar.organizer_mode")].each { |label| assert_link label, visible: :visible }
    end
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  ensure
    window&.resize_to(size.width, size.height) if size
  end
end
