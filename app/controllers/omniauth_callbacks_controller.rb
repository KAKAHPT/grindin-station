# frozen_string_literal: true

# Return leg of "Sign in with Google / Discord" (the request leg is the OmniAuth middleware).
class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access

  def create
    user = Accounts::ConnectIdentity.call(auth: request.env["omniauth.auth"], current_user: current_user)
    start_new_session_for user
    redirect_to after_authentication_url, notice: t("flash.notice.signed_in")
  rescue ActiveRecord::RecordInvalid
    redirect_to new_session_path, alert: t("auth.oauth_failed")
  end

  def failure
    redirect_to new_session_path, alert: t("auth.oauth_failed")
  end
end
