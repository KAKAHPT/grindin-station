# frozen_string_literal: true

require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  test "default locale is en and every en key is translated" do
    I18n.backend.send(:init_translations)
    assert_equal :en, I18n.default_locale
    en = I18n.backend.send(:translations)[:en]
    pt = I18n.backend.send(:translations)[:pt]
    missing = flatten_keys(en) - flatten_keys(pt)
    assert_empty missing, "missing pt keys: #{missing.join(', ')}"
  end

  test "html lang follows the locale, and ?locale= is remembered" do
    get root_path
    assert_select "html[lang=en]"
    get root_path(locale: "pt")
    assert_select "html[lang=pt]"
    get root_path
    assert_select "html[lang=pt]"
    get root_path(locale: "en")
    assert_select "html[lang=en]"
  end

  test "the switch stores the locale cookie and returns to the same page" do
    post locale_path, params: { locale: "es" }, headers: { "Referer" => "http://www.example.com/events?page=2" }

    assert_redirected_to "http://www.example.com/events?page=2"
    assert_equal "es", cookies[:locale]
    set_cookie = Array(response.headers["Set-Cookie"]).join("\n")[/locale=es[^\n]*/]
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/expires=/i, set_cookie)

    get events_path
    assert_select "html[lang=es]"
    get root_path
    assert_select "html[lang=es]"
  end

  test "the switch drops the page's ?locale= so the new choice sticks" do
    post locale_path, params: { locale: "es" }, headers: { "Referer" => "http://www.example.com/events?locale=pt" }

    assert_redirected_to "http://www.example.com/events"
    follow_redirect!
    assert_select "html[lang=es]"
  end

  test "the switch keeps the page's array params" do
    post locale_path, params: { locale: "es" },
                      headers: { "Referer" => "http://www.example.com/events?locale=pt&tags%5B%5D=a&tags%5B%5D=b" }

    assert_redirected_to "http://www.example.com/events?tags%5B%5D=a&tags%5B%5D=b"
  end

  test "the public API sets no locale cookie" do
    tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    tournament.update!(state: :registration_open) if tournament.draft?

    get "/api/v1/events/#{tournament.slug}/info", params: { locale: "pt" }

    assert_response :success
    assert_no_match(/locale=/, Array(response.headers["Set-Cookie"]).join("\n"))
  end

  test "the switch ignores another host's referer" do
    post locale_path, params: { locale: "pt" }, headers: { "Referer" => "https://evil.example/x" }

    assert_redirected_to root_path
  end

  test "?locale= overrides the cookie and updates it" do
    post locale_path, params: { locale: "es" }
    get events_path(locale: "pt")

    assert_select "html[lang=pt]"
    assert_equal "pt", cookies[:locale]
  end

  test "an unknown locale is ignored by the switch and by the param" do
    post locale_path, params: { locale: "pt" }
    post locale_path, params: { locale: "xx" }

    assert_response :see_other
    assert_equal "pt", cookies[:locale]
    get root_path(locale: "xx")
    assert_select "html[lang=pt]"
  end

  test "without param or cookie the browser's Accept-Language decides" do
    get root_path, headers: { "Accept-Language" => "fr-FR,pt;q=0.9,es;q=0.8" }
    assert_select "html[lang=pt]"
    get root_path, headers: { "Accept-Language" => "de" }
    assert_select "html[lang=en]"
  end

  test "the cookie wins over Accept-Language" do
    post locale_path, params: { locale: "es" }
    get root_path, headers: { "Accept-Language" => "pt-PT" }

    assert_select "html[lang=es]"
  end

  test "unknown locale falls back to the default" do
    get root_path(locale: "xx")
    assert_response :success
    assert_select "html[lang=en]"
  end

  PLURAL_KEYS = %i[zero one two few many other].freeze

  private

  # A hash made only of plural forms counts as a single key: languages may translate a plain string as plural forms.
  def flatten_keys(hash, prefix = nil)
    hash.flat_map do |k, v|
      key = [prefix, k].compact.join(".")
      v.is_a?(Hash) && !(v.keys - PLURAL_KEYS).empty? ? flatten_keys(v, key) : [key]
    end
  end
end
