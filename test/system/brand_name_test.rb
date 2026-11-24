# frozen_string_literal: true

require "application_system_test_case"

# The site's name sits beside the mark in the top bar and leads home; it fits a phone without pushing the bar wider.
class BrandNameTest < ApplicationSystemTestCase
  test "the name shows beside the mark, links home and fits a phone" do
    visit events_path
    assert_selector ".topbar-brand [data-brand-name]", text: I18n.t("app.name"), visible: :visible

    page.driver.browser.manage.window.resize_to(375, 800)
    assert_selector ".topbar-brand [data-brand-name]", visible: :visible
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")

    find(".topbar-brand").click
    assert_current_path root_path, ignore_query: true
  end
end
