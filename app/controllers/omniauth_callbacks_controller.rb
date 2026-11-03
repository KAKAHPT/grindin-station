# frozen_string_literal: true

# Return leg of "Sign in with Google / Discord" (the request leg is the OmniAuth middleware).
class OmniauthCallbacksController < ApplicationController
  PROVIDER_NAMES = { "google_oauth2" => "Google", "discord" => "Discord" }.freeze

  allow_unauthenticated_access

  def create
    user = Accounts::ConnectIdentity.call(auth: request.env["omniauth.auth"], current_user: current_user)
    start_new_session_for user
    redirect_to after_authentication_url, notice: t("flash.notice.signed_in")
  rescue Accounts::ConnectIdentity::UnverifiedEmail
    back_to_sign_in t("auth.email_unverified", provider: PROVIDER_NAMES[params[:provider]])
  rescue ActiveRecord::RecordInvalid
    back_to_sign_in t("auth.oauth_failed")
  end

  def failure
    back_to_sign_in t("auth.oauth_failed")
  end

  private

  def back_to_sign_in(alert)
    redirect_to new_session_path, alert: alert
  end
end
