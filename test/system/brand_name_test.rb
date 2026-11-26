# frozen_string_literal: true

require "application_system_test_case"

# The mark alone sits at the start of the top bar and leads home; Home is the first link beside it, in the same
# type as the other links. It fits a phone without pushing the bar wider.
class BrandNameTest < ApplicationSystemTestCase
  test "the mark leads home, Home is the first link and the bar fits a phone" do
    visit events_path
    assert_selector ".topbar-brand .gslogo", visible: :visible
    assert_equal "Home", first(".topbar-links a").text

    window = page.driver.browser.manage.window
    size = window.size
    window.resize_to(375, 800)
    assert_selector ".topbar-brand .gslogo", visible: :visible
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

  test "on a phone the viewer's menu hangs from the right edge of the bar, not from the picture" do
    sign_in_as(users(:organizer_user))
    use_phone_viewport(width: 375, height: 812)
    visit events_path

    find("[data-user-menu] .topbar-me-trigger").click
    assert_selector "[data-user-menu-panel] a", visible: :visible
    gap = page.evaluate_script(<<~JS)
      window.innerWidth - document.querySelector(".topbar-me-menu").getBoundingClientRect().right
    JS
    assert_operator gap, :<=, 16, "the menu sits at the right edge"
    assert_operator gap, :>=, 0, "and stays on the screen"
  end
end
