# frozen_string_literal: true

require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  test "default locale is pt and every en key is translated" do
    I18n.backend.send(:init_translations)
    assert_equal :pt, I18n.default_locale
    en = I18n.backend.send(:translations)[:en]
    pt = I18n.backend.send(:translations)[:pt]
    missing = flatten_keys(en) - flatten_keys(pt)
    assert_empty missing, "missing pt keys: #{missing.join(', ')}"
  end

  test "html lang follows the locale" do
    get root_path
    assert_select "html[lang=pt]"
    get root_path(locale: "en")
    assert_select "html[lang=en]"
  end

  test "unknown locale falls back to the default" do
    get root_path(locale: "xx")
    assert_response :success
    assert_select "html[lang=pt]"
  end

  private

  def flatten_keys(hash, prefix = nil)
    hash.flat_map { |k, v| key = [prefix, k].compact.join("."); v.is_a?(Hash) ? flatten_keys(v, key) : [key] }
  end
end
