# frozen_string_literal: true

class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  layout "auth"
  # Per e-mail against password guessing; per address only loosely, since a venue's players share one.
  rate_limit to: 10, within: 3.minutes, only: :create, name: "email",
             by: -> { login_email },
             with: -> { redirect_to new_session_url, alert: t("flash.alert.try_again_later") }
  rate_limit to: 100, within: 3.minutes, only: :create, name: "ip",
             with: -> { redirect_to new_session_url, alert: t("flash.alert.try_again_later") }

  def new; end

  def create
    credentials = params.expect(session: [:email_address, :password])
    if (user = User.authenticate_by(email_address: credentials[:email_address].to_s,
                                    password: credentials[:password].to_s))
      start_new_session_for user
      Audit.record(:sign_in, actor: user, subject: user)
      redirect_to root_path, notice: t("flash.notice.signed_in")
    else
      Audit.record(:sign_in_failed, actor: nil, email: login_email)
      redirect_to new_session_path, alert: t("flash.alert.invalid_credentials")
    end
  end

  def destroy
    Audit.record(:sign_out, subject: Current.user)
    terminate_session
    redirect_to root_path, notice: t("flash.notice.signed_out")
  end

  private

  # The e-mail the rate limit counts by; "" for a malformed body (params.expect answers it with a 400).
  def login_email
    session_params = params[:session]
    session_params.is_a?(ActionController::Parameters) ? session_params[:email_address].to_s.strip.downcase : ""
  end
end
