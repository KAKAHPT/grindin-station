# frozen_string_literal: true

require "test_helper"

# The public sign-up's e-mail confirmation: link, expiry, resend, and the sign-in gate.
class ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  include RateLimitStore

  setup do
    post registrations_path, params: { user: { name: "Fresh", email_address: "fresh@example.com",
                                               password: "eightch8", password_confirmation: "eightch8" } }
    @user = User.find_by!(email_address: "fresh@example.com")
  end

  test "an unconfirmed account cannot sign in with its password" do
    post session_path, params: { session: { email_address: "fresh@example.com", password: "eightch8" } }

    assert_redirected_to new_session_path
    assert_equal I18n.t("flash.alert.confirm_first"), flash[:alert]
    assert_empty @user.sessions
  end

  test "the link confirms the account and signs the user in; a second visit is harmless" do
    token = @user.generate_token_for(:email_confirmation)

    get confirmation_path(token)

    assert_redirected_to root_path
    assert_equal I18n.t("flash.notice.email_confirmed"), flash[:notice]
    assert @user.reload.confirmed?
    assert_equal 1, @user.sessions.count
    assert_equal 1, AuditEvent.where(action: "email_confirmed", subject: @user).count

    post session_path, params: { session: { email_address: "fresh@example.com", password: "eightch8" } }
    assert_redirected_to root_path
  end

  test "a tampered, expired or e-mail-changed link is refused" do
    get confirmation_path("not-a-token")
    assert_redirected_to new_confirmation_path
    assert_equal I18n.t("flash.alert.confirm_link_invalid"), flash[:alert]

    token = @user.generate_token_for(:email_confirmation)
    travel 3.days do
      get confirmation_path(token)
      assert_redirected_to new_confirmation_path
    end

    token = @user.generate_token_for(:email_confirmation)
    @user.update!(email_address: "moved@example.com")
    get confirmation_path(token)
    assert_redirected_to new_confirmation_path
    assert_not @user.reload.confirmed?
  end

  test "the resend page shows the e-mail form" do
    get new_confirmation_path

    assert_response :success
    assert_select "form[action=?] input[type=email]", confirmations_path
  end

  test "the confirmation mail can be sent again, with the same answer for unknown addresses" do
    assert_emails 1 do
      post confirmations_path, params: { email_address: "Fresh@Example.com" }
    end
    assert_redirected_to new_session_path
    assert_equal I18n.t("flash.notice.confirmation_resent"), flash[:notice]

    assert_emails 0 do
      post confirmations_path, params: { email_address: "nobody@example.com" }
      post confirmations_path, params: { email_address: users(:player_one).email_address }
    end
    assert_equal I18n.t("flash.notice.confirmation_resent"), flash[:notice]
  end

  test "resending is limited to five per address in ten minutes" do
    with_memory_rate_limit_store do
      5.times { post confirmations_path, params: { email_address: "fresh@example.com" } }
      post confirmations_path, params: { email_address: "fresh@example.com" }
      assert_redirected_to new_confirmation_url
      assert_equal I18n.t("flash.alert.try_again_later"), flash[:alert]
    end
  end

  test "accounts created any other way are confirmed from the start" do
    organizer_added = User.create!(name: "Added", email_address: "added@example.com", password: "password123")
    assert organizer_added.confirmed?
    assert users(:player_one).confirmed?
  end
end
