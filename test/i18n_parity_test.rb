# frozen_string_literal: true

require "test_helper"

# en, pt and es carry the same keys: the app's own files (config/locales/{en,pt,es}.yml) key for key with no empty
# copy, and the loaded translations (framework keys included: dates, numbers, errors) cover every en key.
class I18nParityTest < ActiveSupport::TestCase
  LOCALES = %i[en pt es].freeze
  PLURAL_KEYS = %i[zero one two few many other].freeze

  test "the available locales are en, pt and es" do
    assert_equal LOCALES, I18n.available_locales
  end

  test "the app locale files have identical keys and no empty strings" do
    keys =
      LOCALES.index_with do |locale|
        leaves(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml")).fetch(locale.to_s))
      end

    LOCALES.drop(1).each do |locale|
      assert_empty keys[:en].keys - keys[locale].keys, "keys missing in #{locale}"
      assert_empty keys[locale].keys - keys[:en].keys, "keys in #{locale} but not in en"
    end
    LOCALES.each do |locale|
      empty = keys[locale].select { |_, value| value.is_a?(String) && value.strip.empty? }.keys
      assert_empty empty, "empty strings in #{locale}"
    end
  end

  test "the loaded translations, framework keys included, match across locales" do
    I18n.backend.send(:init_translations)
    translations = I18n.backend.send(:translations)
    keys = LOCALES.index_with { |locale| translation_keys(translations.fetch(locale)) }

    LOCALES.drop(1).each { |locale| assert_empty keys[:en] - keys[locale], "keys missing in #{locale}" }
    # pt and es also translate dev-only framework messages (web-console, sessions) the test env does not load in en.
    assert_equal keys[:pt].sort, keys[:es].sort
  end

  test "es formats dates and pluralizes" do
    assert_equal "04 de noviembre de 2026", I18n.l(Date.new(2026, 11, 4), format: :long, locale: :es)
    assert_equal "3 rondas suizas", I18n.t("organizer.shell.swiss_rounds", count: 3, locale: :es)
    assert_equal "1 ronda suiza", I18n.t("organizer.shell.swiss_rounds", count: 1, locale: :es)
  end

  private

  # Every leaf with its value; arrays (day names, landing steps) are leaves.
  def leaves(hash, prefix = nil)
    hash.each_with_object({}) do |(key, value), out|
      path = [prefix, key].compact.join(".")
      value.is_a?(Hash) ? out.merge!(leaves(value, path)) : out[path] = value
    end
  end

  # A hash made only of plural forms counts as one key: a language may use plural forms for a plain string.
  def translation_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [prefix, key].compact.join(".")
      value.is_a?(Hash) && !(value.keys - PLURAL_KEYS).empty? ? translation_keys(value, path) : [path]
    end
  end
end
