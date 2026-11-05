# frozen_string_literal: true

require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  include RateLimitStore

  setup do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "g-123", info: { email: "player1@example.com", name: "Player One" },
      extra: { raw_info: { email: "player1@example.com", email_verified: true } }
    )
  end

  test "callback with a new verified e-mail creates the user, signs in and redirects" do
    mock_email("new@example.com")
    OmniAuth.config.mock_auth[:google_oauth2].info.name = "New Person"

    assert_difference -> { Session.count } => 1, -> { Identity.count } => 1, -> { User.count } => 1 do
      post "/auth/google_oauth2"
      follow_redirect!
    end

    assert_redirected_to root_url
    assert cookies[:session_id].present?
    assert_equal "new@example.com", Identity.find_by(uid: "g-123").user.email_address
  end

  test "known identity signs its owner in" do
    users(:player_two).identities.create!(provider: "google_oauth2", uid: "g-123")

    assert_difference -> { Session.count } => 1 do
      post "/auth/google_oauth2"
      follow_redirect!
    end

    assert_equal users(:player_two), Session.last.user
  end

  test "verified e-mail of an existing account is refused without linking or a session" do
    assert_no_difference [-> { Session.count }, -> { Identity.count }] do
      post "/auth/google_oauth2"
      follow_redirect!
    end

    assert_redirected_to new_session_path
    assert_equal I18n.t("auth.email_taken", provider: "Google"), flash[:alert]
  end

  test "unverified e-mail without an account never creates a user" do
    mock_email("fresh@example.com", verified: false)

    assert_no_difference [-> { User.count }, -> { Session.count }, -> { Identity.count }] do
      post "/auth/google_oauth2"
      follow_redirect!
    end

    assert_redirected_to new_session_path
    assert_equal I18n.t("auth.email_unverified", provider: "Google"), flash[:alert]
  end

  test "signed in, the callback links to the current user and returns to the account page" do
    sign_in users(:player_three)
    mock_email("someone-else@example.com")

    assert_no_difference -> { Session.count } do
      assert_difference -> { Identity.count }, 1 do
        post "/auth/google_oauth2"
        follow_redirect!
      end
    end

    assert_redirected_to account_path
    assert_equal I18n.t("auth.linked", provider: "Google"), flash[:notice]
    assert_equal users(:player_three), Identity.find_by(uid: "g-123").user
  end

  test "signed in, an identity of another user is refused and the session stays" do
    users(:player_two).identities.create!(provider: "google_oauth2", uid: "g-123")
    sign_in users(:player_three)
    session_id = Session.last.id

    assert_no_difference [-> { Session.count }, -> { Identity.count }] do
      post "/auth/google_oauth2"
      follow_redirect!
    end

    assert_redirected_to account_path
    assert_equal I18n.t("auth.identity_taken", provider: "Google"), flash[:alert]
    assert_equal users(:player_two), Identity.find_by(uid: "g-123").user
    get account_path
    assert_response :success
    assert_equal users(:player_three), Session.find(session_id).user
  end

  test "unverified e-mail of an existing account is refused without a session" do
    OmniAuth.config.mock_auth[:google_oauth2].extra.raw_info.email_verified = false

    assert_no_difference [-> { Session.count }, -> { Identity.count }] do
      post "/auth/google_oauth2"
      follow_redirect!
    end

    assert_redirected_to new_session_path
    assert_equal I18n.t("auth.email_unverified", provider: "Google"), flash[:alert]
  end

  test "failure redirects to the sign in page with an alert" do
    get "/auth/failure", params: { message: "invalid_credentials", strategy: "google_oauth2" }

    assert_redirected_to new_session_path
    assert_equal I18n.t("auth.oauth_failed"), flash[:alert]
  end

  test "failure is throttled after 20 requests" do
    with_memory_rate_limit_store do
      20.times { get "/auth/failure", params: { message: "x", strategy: "discord" } }
      assert_equal I18n.t("auth.oauth_failed"), flash[:alert]

      get "/auth/failure", params: { message: "x", strategy: "discord" }
      assert_redirected_to new_session_path
      assert_equal I18n.t("flash.alert.try_again_later"), flash[:alert]
    end
  end

  test "failure stores an unknown strategy as unknown and truncates the reason" do
    get "/auth/failure", params: { message: "a" * 300, strategy: "evil" }

    audit = AuditEvent.recent.first
    assert_equal "oauth_failed", audit.action
    assert_equal "unknown", audit.data["provider"]
    assert_equal 64, audit.data["reason"].length
  end

  test "mocked provider error ends on the sign in page" do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials

    post "/auth/google_oauth2"
    follow_redirect!
    follow_redirect!

    assert_redirected_to new_session_path
  end

  test "sign in page shows provider buttons only when configured" do
    with_env("GOOGLE_CLIENT_ID" => "id", "DISCORD_CLIENT_ID" => nil) do
      get new_session_path
    end

    assert_select "form[action='/auth/google_oauth2'][method='post']"
    assert_select "form[action='/auth/discord']", count: 0
  end

  private

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end

  def mock_email(email, verified: true)
    auth = OmniAuth.config.mock_auth[:google_oauth2]
    auth.info.email = email
    auth.extra.raw_info.email = email
    auth.extra.raw_info.email_verified = verified
  end

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
