# frozen_string_literal: true

require "test_helper"

class IconHelperTest < ActionView::TestCase
  tests ApplicationHelper

  SPRITE = Rails.root.join("app/assets/images/icons.svg")

  # Every icon name the app can ask for: literal icon("...") calls and icon: "..." entries in app/,
  # plus the result icons chosen at runtime.
  def used_icon_names
    names =
      Rails.root.glob("app/**/*.{erb,rb}").flat_map do |file|
        source = File.read(file)
        source.scan(/\bicon\(\s*["']([a-z0-9-]+)["']/).flatten +
          source.scan(/\bicon:\s*["']([a-z0-9-]+)["']/).flatten
      end
    (names + ApplicationHelper::RESULT_ICONS.values).uniq.sort
  end

  test "the sprite has a symbol for every icon used in the app" do
    symbols = File.read(SPRITE).scan(/<symbol id="([a-z0-9-]+)"/).flatten

    assert_operator used_icon_names.size, :>=, 30
    assert_empty used_icon_names - symbols, "icons missing from #{SPRITE.basename}"
  end

  test "icon references the sprite and keeps the extra classes" do
    html = icon("trophy", class: "me-2 text-accent")
    svg = Nokogiri::HTML5.fragment(html).at("svg")

    assert_equal "true", svg["aria-hidden"]
    assert_equal "currentColor", svg["fill"]
    assert_includes svg["class"].split, "me-2"
    assert_includes svg["class"].split, "text-accent"
    assert_equal "#{asset_path('icons.svg')}#trophy", svg.at("use")["href"]
  end
end
