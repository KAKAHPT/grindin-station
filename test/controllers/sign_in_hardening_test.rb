# frozen_string_literal: true

require "test_helper"

class SignInHardeningTest < ActionDispatch::IntegrationTest
  include RateLimitStore

  def sign_in_as(email, password = "wrong-password", ip: "10.0.0.1")
    post session_path, params: { session: { email_address: email, password: password } },
                       env: { "REMOTE_ADDR" => ip }
  end

  def request_reset(email, ip: "10.0.0.1")
    post passwords_path, params: { email_address: email }, env: { "REMOTE_ADDR" => ip }
  end

  def sign_up(email)
    post registrations_path, params: { user: { name: "Player", email_address: email, password: "password123",
                                               password_confirmation: "password123" } }
  end

  test "ten failed sign-ins for one e-mail lock that e-mail, not the address" do
    with_memory_rate_limit_store do
      10.times { |i| sign_in_as("player1@example.com", ip: "10.0.0.#{i + 1}") }
      sign_in_as("player1@example.com", "password123", ip: "10.0.1.1")
      assert_equal I18n.t("flash.alert.try_again_later"), flash[:alert]

      sign_in_as("player2@example.com", "password123")
      assert_equal I18n.t("flash.notice.signed_in"), flash[:notice]
    end
  end

  test "one venue address allows many players to sign in" do
    with_memory_rate_limit_store do
      30.times { |i| sign_in_as("someone#{i}@example.com") }
      sign_in_as("player2@example.com", "password123")
      assert_equal I18n.t("flash.notice.signed_in"), flash[:notice]
    end
  end

  test "a session older than 30 days is ended" do
    sign_in_as("player1@example.com", "password123")
    session_row = users(:player_one).sessions.sole
    get account_path
    assert_response :success

    session_row.update!(created_at: 31.days.ago)
    get account_path

    assert_redirected_to new_session_path
    assert_not Session.exists?(session_row.id)
  end

  test "the session cookie expires" do
    sign_in_as("player1@example.com", "password123")

    assert_match(/expires=/i, response.headers["Set-Cookie"].to_s[/session_id=[^\n]*/])
  end

  test "password reset requests are limited per e-mail and per address" do
    with_memory_rate_limit_store do
      5.times { |i| request_reset("player1@example.com", ip: "10.0.2.#{i}") }
      request_reset("player1@example.com", ip: "10.0.3.1")
      assert_equal I18n.t("flash.alert.try_again_later"), flash[:alert]

      5.times { |i| request_reset("other#{i}@example.com") }
      request_reset("player2@example.com")
      assert_equal I18n.t("flash.alert.try_again_later"), flash[:alert]
    end
  end

  test "sign-ups allow 30 per address" do
    with_memory_rate_limit_store do
      30.times { |i| sign_up("p#{i}@example.com") }
      assert_equal I18n.t("flash.notice.welcome_signed_up"), flash[:notice]

      sign_up("extra@example.com")
      assert_equal I18n.t("flash.alert.try_again_later"), flash[:alert]
    end
  end
end
