# frozen_string_literal: true

# Return leg of "Sign in with Google / Discord" (the request leg is the OmniAuth middleware).
class OmniauthCallbacksController < ApplicationController
  PROVIDER_NAMES = { "google_oauth2" => "Google", "discord" => "Discord" }.freeze

  # Refusals that send the visitor back to the sign-in page, with the alert to show.
  REFUSALS = { Accounts::ConnectIdentity::UnverifiedEmail => "auth.email_unverified",
               Accounts::ConnectIdentity::EmailTaken => "auth.email_taken" }.freeze

  allow_unauthenticated_access
  rescue_from(*REFUSALS.keys) do |error|
    audit_failure(error)
    back_to_sign_in t(REFUSALS.fetch(error.class), provider: provider_name)
  end
  rescue_from(Accounts::ConnectIdentity::IdentityTaken) do |error|
    audit_failure(error)
    redirect_to account_path, alert: t("auth.identity_taken", provider: provider_name)
  end
  rescue_from(ActiveRecord::RecordInvalid) do |error|
    audit_failure(error)
    back_to_sign_in t("auth.oauth_failed")
  end

  # Signed in, the identity is linked to the current user (from the account page); otherwise it signs in.
  def create
    signed_in = current_user
    user = Accounts::ConnectIdentity.call(auth: request.env["omniauth.auth"], current_user: signed_in)
    return redirect_to(account_path, notice: t("auth.linked", provider: provider_name)) if signed_in

    start_new_session_for user
    Audit.record(:oauth_sign_in, actor: user, subject: user, provider: params[:provider])
    redirect_to after_authentication_url, notice: t("flash.notice.signed_in")
  end

  # OmniAuth sends the strategy and its error key (e.g. "invalid_credentials").
  def failure
    Audit.record(:oauth_failed, provider: params[:strategy].to_s, reason: params[:message].to_s)
    back_to_sign_in t("auth.oauth_failed")
  end

  private

  def audit_failure(error)
    Audit.record(:oauth_failed, provider: params[:provider].to_s, reason: error.class.name.demodulize.underscore)
  end

  def provider_name
    PROVIDER_NAMES.fetch(params[:provider], params[:provider])
  end

  def back_to_sign_in(alert)
    redirect_to new_session_path, alert: alert
  end
end
