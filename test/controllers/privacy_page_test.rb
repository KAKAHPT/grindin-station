# frozen_string_literal: true

require "test_helper"

# /privacy: the privacy notice in the three languages, linked from every page layout's footer and from the two forms
# that collect an e-mail without an account (sign-up, organiser waiting list).
class PrivacyPageTest < ActionDispatch::IntegrationTest
  test "renders without signing in, with the rights, retention and the complaint authority" do
    get privacy_path

    assert_response :success
    assert_select "h1", text: "Privacy"
    assert_select "[data-privacy] h2", text: "Your rights"
    assert_select "[data-privacy] li", text: "Security log: 12 months."
    assert_select "[data-privacy] a[href='https://www.cnpd.pt']"
    assert_select "[data-privacy] a[href=?]", account_path, text: "Account"
  end

  test "is translated" do
    get privacy_path(locale: "pt")
    assert_select "h1", text: "Privacidade"
    assert_select "[data-privacy] h2", text: "Os teus direitos"

    get privacy_path(locale: "es")
    assert_select "h1", text: "Privacidad"
    assert_select "[data-privacy] h2", text: "Tus derechos"
  end

  test "the public, application and play layouts link to it in the footer" do
    get root_path
    assert_select "footer a[data-privacy-link][href=?]", privacy_path

    get events_path
    assert_select "footer a[data-privacy-link][href=?]", privacy_path

    get play_event_path(events(:medium_tournament_registration_open).slug)
    assert_select "footer a[data-privacy-link][href=?]", privacy_path
  end

  test "the sign-up form and the waiting list point to it" do
    get new_registration_path
    assert_select "#signup-form [data-privacy-notice] a[href=?]", privacy_path, text: "Privacy"

    get root_path
    assert_select "#waitlist [data-privacy-notice] a[href=?]", privacy_path, text: "Privacy"
  end
end
