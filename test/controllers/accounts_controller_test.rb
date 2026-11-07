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

  test "the account page is cards with title bands and Settings-look fields" do
    get account_path

    assert_select "[data-account] section.card", count: 5
    assert_select "[data-account] section.card > .card-title", count: 5
    assert_select "[data-account] .field input.field-input[name='user[name]']"
    assert_no_match(/purple|orange-700|dark:|gray-\d/, css_select("[data-account]").to_html)
  end

  test "link buttons only for enabled providers that are not linked yet" do
    @user.identities.create!(provider: "discord", uid: "d-1", name: "p1")

    with_env("GOOGLE_CLIENT_ID" => "id", "DISCORD_CLIENT_ID" => "id") { get account_path }

    assert_select "form[action='/auth/google_oauth2'][method='post']"
    assert_select "form[action='/auth/discord']", count: 0

    with_env("GOOGLE_CLIENT_ID" => nil, "DISCORD_CLIENT_ID" => nil) { get account_path }

    assert_select "form[action^='/auth/']", count: 0
  end

  test "updates the profile fields" do
    patch account_path, params: { user: { name: "Player Uno", handle: "uno", country: "pt", bio: "Hi",
                                          visibility: "participants" } }

    assert_redirected_to account_path
    @user.reload
    assert_equal ["Player Uno", "uno", "PT", "Hi", "participants"],
                 [@user.name, @user.handle, @user.country, @user.bio, @user.visibility]
  end

  test "the account page shows the Team card with create and join forms" do
    Team.create!(name: "Lisbon Lords", owner: users(:player_two))

    get account_path

    assert_select "input[name='user[team]']", count: 0
    assert_select "[data-team-card] [data-team-create] input[name='team[name]']"
    assert_select "[data-team-card] [data-team-join] option", text: "Lisbon Lords"
  end
  test "shows the Wizards e-mail field with its hint" do
    get account_path

    assert_select "input[name='user[player_attributes][wizards_email]']"
    assert_select "p", text: /report your results to Wizards EventLink/
  end

  test "saves the Wizards e-mail on the player, normalised" do
    patch account_path, params: { user: { player_attributes: { wizards_email: " Wiz@Example.com " } } }

    assert_redirected_to account_path
    assert_equal "wiz@example.com", @user.player.reload.wizards_email
  end

  test "an invalid Wizards e-mail re-renders with an error" do
    patch account_path, params: { user: { player_attributes: { wizards_email: "nope" } } }

    assert_response :unprocessable_content
    assert_nil @user.player.reload.wizards_email
  end

  test "invalid handle re-renders with an error" do
    patch account_path, params: { user: { handle: "No Spaces" } }

    assert_response :unprocessable_entity
    assert_not_equal "No Spaces", @user.reload.handle
  end

  test "an organizer uploads a banner; a player sees no banner field" do
    get account_path
    assert_select "[data-banner-field]", count: 0
    EventOrganizer.create!(user: @user)
    get account_path
    assert_select "input[type=file][name='user[banner]']"

    patch account_path, params: { user: { banner: fixture_file_upload("cover1.jpg", "image/jpeg") } }
    assert @user.reload.banner.attached?

    get organizers_path
    assert_select "[data-organizer='#{@user.handle}'][data-organizer-banner][style*='background-image']"
    get organizer_profile_path(@user.handle)
    assert_select "[data-organizer-header][data-organizer-banner]"
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

  test "an e-mail change needs the current password and waits for the link sent to the new address" do
    patch account_path, params: { user: { email_address: "new@example.com", current_password: "wrong" } }
    assert_response :unprocessable_entity
    assert_equal "player1@example.com", @user.reload.email_address

    assert_emails 1 do
      patch account_path, params: { user: { email_address: "New@Example.com", current_password: "password123" } }
    end
    assert_redirected_to account_path
    assert_equal I18n.t("accounts.flash.email_change_sent", email: "new@example.com"), flash[:notice]
    assert_equal "player1@example.com", @user.reload.email_address, "not applied yet"
    assert_equal "new@example.com", @user.unconfirmed_email
    get account_path
    assert_select "[data-pending-email]", text: /new@example.com/

    get confirmation_path(@user.generate_token_for(:email_change))
    assert_redirected_to account_path
    assert_equal "new@example.com", @user.reload.email_address
    assert_nil @user.unconfirmed_email
    assert_equal 1, AuditEvent.where(action: "email_changed").count
  end

  test "a pending e-mail change is refused if the address was taken meanwhile, and its link is single-use" do
    patch account_path, params: { user: { email_address: "taken@example.com", current_password: "password123" } }
    token = @user.reload.generate_token_for(:email_change)
    users(:player_two).update!(email_address: "taken@example.com")

    get confirmation_path(token)
    assert_redirected_to new_session_path
    assert_equal "player1@example.com", @user.reload.email_address

    @user.update!(unconfirmed_email: "free@example.com")
    token = @user.generate_token_for(:email_change)
    get confirmation_path(token)
    assert_equal "free@example.com", @user.reload.email_address
    get confirmation_path(token)
    assert_redirected_to new_confirmation_path, "the payload (the pending address) is gone, so the link is dead"
  end

  test "resubmitting the same e-mail needs no password" do
    patch account_path, params: { user: { email_address: " Player1@example.com", name: "Renamed" } }

    assert_redirected_to account_path
    assert_equal "Renamed", @user.reload.name
  end

  test "a password or e-mail change ends the other sessions, keeping this one" do
    other = @user.sessions.create!(user_agent: "other device")

    patch account_path, params: { user: { password: "newpassword1", password_confirmation: "newpassword1",
                                          current_password: "password123" } }
    assert_not Session.exists?(other.id)
    assert_equal 1, @user.sessions.count

    other = @user.sessions.create!(user_agent: "other device")
    patch account_path, params: { user: { email_address: "moved@example.com", current_password: "newpassword1" } }
    assert Session.exists?(other.id), "a pending change ends nothing yet"
    get confirmation_path(@user.reload.generate_token_for(:email_change))
    assert_not Session.exists?(other.id), "applying the change starts over with one session"
    get account_path
    assert_response :success
  end

  test "a profile change keeps the other sessions" do
    other = @user.sessions.create!(user_agent: "other device")

    patch account_path, params: { user: { bio: "Hello" } }

    assert Session.exists?(other.id)
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

  private

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
