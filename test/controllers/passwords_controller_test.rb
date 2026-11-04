# frozen_string_literal: true

require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "a reset marks the password as set for an OAuth-created user" do
    user = users(:player_one)
    user.update!(password_set: false)

    put password_path(user.password_reset_token),
        params: { password: "new-pass-123", password_confirmation: "new-pass-123" }

    assert_redirected_to new_session_path
    assert user.reload.password_set
    assert user.authenticate("new-pass-123")
  end

  test "a mismatched confirmation changes nothing" do
    user = users(:player_one)
    user.update!(password_set: false)

    put password_path(user.password_reset_token),
        params: { password: "new-pass-123", password_confirmation: "other-123" }

    assert_response :redirect
    assert_match %r{/passwords/[^/]+/edit\z}, response.location
    assert_not user.reload.password_set
  end

  test "a blank or short password is rejected and keeps the sessions" do
    user = users(:player_one)
    user.update!(password_set: false)
    user.sessions.create!(user_agent: "other device")

    ["", "short"].each do |password|
      put password_path(user.password_reset_token), params: { password: password, password_confirmation: password }

      assert_match %r{/passwords/[^/]+/edit\z}, response.location
      assert_equal I18n.t("flash.alert.passwords_no_match"), flash[:alert]
    end
    user.reload
    assert_not user.password_set
    assert user.authenticate("password123")
    assert_predicate user.sessions, :exists?
  end

  test "an invalid token goes back to the reset request" do
    get edit_password_path("not-a-token")

    assert_redirected_to new_password_path
  end
end
