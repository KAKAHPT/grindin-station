# frozen_string_literal: true

require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "g-123", info: { email: "player1@example.com", name: "Player One" }
    )
  end

  test "callback signs the user in and redirects to after_authentication_url" do
    assert_difference -> { Session.count } => 1, -> { Identity.count } => 1 do
      post "/auth/google_oauth2"
      follow_redirect!
    end

    assert_redirected_to root_url
    assert cookies[:session_id].present?
    assert_equal users(:player_one), Identity.find_by(uid: "g-123").user
  end

  test "failure redirects to the sign in page with an alert" do
    get "/auth/failure", params: { message: "invalid_credentials", strategy: "google_oauth2" }

    assert_redirected_to new_session_path
    assert_equal I18n.t("auth.oauth_failed"), flash[:alert]
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

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
