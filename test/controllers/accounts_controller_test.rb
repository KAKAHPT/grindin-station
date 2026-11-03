# frozen_string_literal: true

require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  setup do
    @user = users(:player_one)
    post session_path, params: { session: { email_address: @user.email_address, password: "password123" } }
  end

  test "account page requires a session" do
    delete session_path(Session.last)

    get account_path

    assert_redirected_to new_session_path
  end

  test "shows the profile, identities and delete form" do
    @user.identities.create!(provider: "discord", uid: "d-1", name: "p1")

    get account_path

    assert_response :success
    assert_select "input[name='user[handle]'][value=?]", @user.handle
    assert_select "select[name='user[visibility]']"
    assert_select "input[type=file][name='user[avatar]']"
    assert_select "form[action=?]", unlink_identity_path(@user.identities.first)
    assert_select "input[name=confirmation]"
  end

  test "updates the profile fields" do
    patch account_path, params: { user: { name: "Player Uno", handle: "uno", country: "pt", bio: "Hi",
                                          visibility: "participants" } }

    assert_redirected_to account_path
    @user.reload
    assert_equal ["Player Uno", "uno", "PT", "Hi", "participants"],
                 [@user.name, @user.handle, @user.country, @user.bio, @user.visibility]
  end

  test "invalid handle re-renders with an error" do
    patch account_path, params: { user: { handle: "No Spaces" } }

    assert_response :unprocessable_entity
    assert_not_equal "No Spaces", @user.reload.handle
  end

  test "uploads an avatar" do
    patch account_path, params: { user: { avatar: fixture_file_upload("cover1.jpg", "image/jpeg") } }

    assert_redirected_to account_path
    assert @user.reload.avatar.attached?
  end

  test "rejects an avatar of the wrong type" do
    gif = Rack::Test::UploadedFile.new(StringIO.new("GIF89a\x01\x00\x01\x00"), "image/gif",
                                       original_filename: "a.gif")

    patch account_path, params: { user: { avatar: gif } }

    assert_response :unprocessable_entity
    assert_not @user.reload.avatar.attached?
  end

  test "password change needs the current password and marks it as set" do
    patch account_path, params: { user: { password: "newpassword1", password_confirmation: "newpassword1",
                                          current_password: "wrong" } }
    assert_response :unprocessable_entity
    assert @user.reload.authenticate("password123")

    patch account_path, params: { user: { password: "newpassword1", password_confirmation: "newpassword1",
                                          current_password: "password123" } }
    assert_redirected_to account_path
    assert @user.reload.authenticate("newpassword1")
    assert @user.password_set
  end

  test "an OAuth-created user sets a password without the current one" do
    @user.update!(password_set: false)

    patch account_path, params: { user: { password: "newpassword1", password_confirmation: "newpassword1" } }

    assert_redirected_to account_path
    assert @user.reload.password_set
    assert @user.authenticate("newpassword1")
  end

  test "unlinks an identity when a password is set" do
    identity = @user.identities.create!(provider: "discord", uid: "d-1")

    assert_difference -> { Identity.count }, -1 do
      delete unlink_identity_path(identity)
    end
    assert_redirected_to account_path
  end

  test "refuses to unlink the last way in of an OAuth-only user" do
    @user.update!(password_set: false)
    identity = @user.identities.create!(provider: "discord", uid: "d-1")

    assert_no_difference -> { Identity.count } do
      delete unlink_identity_path(identity)
    end
    assert_redirected_to account_path
    assert_equal I18n.t("accounts.flash.unlink_refused"), flash[:alert]

    @user.identities.create!(provider: "google_oauth2", uid: "g-1")
    assert_difference -> { Identity.count }, -1 do
      delete unlink_identity_path(identity)
    end
  end

  test "cannot unlink someone else's identity" do
    other = users(:player_two).identities.create!(provider: "discord", uid: "d-2")

    delete unlink_identity_path(other)

    assert_response :not_found
    assert Identity.exists?(other.id)
  end

  test "deletion needs the confirmation word" do
    delete account_path, params: { confirmation: "nope" }

    assert_redirected_to account_path
    assert_nil @user.reload.anonymized_at
  end

  test "deletion anonymises the account and ends the session" do
    delete account_path, params: { confirmation: "delete" }

    assert_redirected_to root_path
    assert_equal I18n.t("accounts.flash.deleted"), flash[:notice]
    assert @user.reload.anonymized_at.present?
    assert_empty @user.sessions

    get account_path
    assert_redirected_to new_session_path
  end

  test "deletion in portuguese needs eliminar" do
    delete account_path(locale: "pt"), params: { confirmation: "delete" }
    assert_nil @user.reload.anonymized_at

    delete account_path(locale: "pt"), params: { confirmation: "eliminar" }
    assert @user.reload.anonymized_at.present?
  end

  test "nav shows the account link" do
    get root_path

    assert_select "a[href=?]", account_path
  end
end
