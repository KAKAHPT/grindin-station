# frozen_string_literal: true

require "test_helper"

# Sign in, sign up, forgot and reset (spec §5): one centred card with the mark and the name above the title, the
# e-mail form first and the "create an account with any e-mail" copy; as a page and inside the modal frame.
class AuthPagesTest < ActionDispatch::IntegrationTest
  PAGES = {
    "sign in" => -> { new_session_path },
    "sign up" => -> { new_registration_path },
    "forgot" => -> { new_password_path },
    "reset" => -> { edit_password_path(users(:player_one).password_reset_token) }
  }.freeze

  PAGES.each do |name, path|
    test "#{name} is the auth card with the mark and the sign-up copy" do
      get instance_exec(&path)

      assert_response :success
      assert_auth_card
    end

    test "#{name} renders the same card inside the modal frame" do
      get instance_exec(&path), headers: { "Turbo-Frame" => "modal" }

      assert_response :success
      assert_select "turbo-frame#modal [data-auth-card]"
      assert_select "[data-topbar]", count: 0
      assert_auth_card
    end
  end

  test "sign in puts e-mail and password before the providers and links sign-up and forgot" do
    get new_session_path

    assert_select "[data-auth-card] h2", text: "Sign in"
    assert_select "[data-auth-card] #session_email_address"
    assert_select "[data-auth-card] #session_password"
    assert_select "[data-sign-up-copy] a[href=?]", new_registration_path, text: "Create an account with any e-mail"
    assert_select "[data-sign-up-copy]", text: /New here\?/
    assert_select "[data-auth-card] a[href=?]", new_password_path, text: "Forgot password?"
  end

  test "the provider buttons are hidden without their env vars" do
    get new_session_path

    assert_select "[data-oauth]", count: 0
  end

  test "the provider buttons come after the e-mail form when configured" do
    with_env("GOOGLE_CLIENT_ID" => "id", "GOOGLE_CLIENT_SECRET" => "secret") do
      get new_session_path
    end

    assert_select "[data-auth-card] #login-form ~ [data-oauth] button", text: "Continue with Google"
  end

  test "the reset request posts the e-mail the controller reads" do
    get new_password_path

    assert_select "#password-reset-form input[type=email][name=email_address]"
  end

  test "the reset page posts the top-level password fields the controller reads" do
    get edit_password_path(users(:player_one).password_reset_token)

    assert_select "#password-reset-form input[type=password][name=password]"
    assert_select "#password-reset-form input[type=password][name=password_confirmation]"
  end

  test "a reset request from the form sends one e-mail and the reset changes the password" do
    user = users(:player_one)

    assert_enqueued_emails 1 do
      post passwords_path, params: { email_address: user.email_address }
    end
    assert_redirected_to new_session_path

    patch password_path(user.password_reset_token),
          params: { password: "brand-new-pass", password_confirmation: "brand-new-pass" }

    assert_redirected_to new_session_path
    assert user.reload.authenticate("brand-new-pass")
  end

  test "posts from the modal frame redirect instead of rendering a stream" do
    post session_path, params: { session: { email_address: "nobody@example.com", password: "wrong-pass" } },
                       headers: { "Turbo-Frame" => "modal" }
    assert_redirected_to new_session_path

    post passwords_path, params: { email_address: users(:player_one).email_address }, headers: { "Turbo-Frame" => "modal" }
    assert_redirected_to new_session_path
  end

  test "the auth pages follow the locale" do
    get new_session_path(locale: "es")

    assert_select "[data-auth-card] h2", text: "Iniciar sesión"
    assert_select "[data-sign-up-copy]", text: /No necesitas Google ni Discord/
    assert_select "[data-auth-card] .field span", text: "obligatorio"
    assert_select "[data-auth-card] label[for=session_email_address] span", text: "Correo electrónico"
    assert_select "[data-auth-card] label[for=session_password] span", text: "Contraseña"
  end

  test "the auth pages use no legacy styling" do
    PAGES.each_value do |path|
      get instance_exec(&path)

      assert_no_match(/purple|orange-700|dark:|gray-\d/, css_select("[data-auth-card]").to_html)
    end
  end

  private

  def assert_auth_card
    assert_select "[data-auth-card] .auth-mark .gslogo", count: 1
    assert_select "[data-auth-card] .auth-mark", text: /Grindin Station/
    assert_select "[data-auth-card] h2", count: 1
    assert_select "[data-auth-card] [data-sign-up-copy]",
                  text: /No Google or Discord needed\. You can link them later from your account\./
  end

  def with_env(values)
    saved = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
