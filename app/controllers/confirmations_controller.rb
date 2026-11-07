# frozen_string_literal: true

# E-mail confirmation of a public sign-up: the link in the mail (show) confirms the address and signs the user
# in; new/create send the link again to an unconfirmed account.
class ConfirmationsController < ApplicationController
  allow_unauthenticated_access
  layout "auth"
  rate_limit to: 20, within: 10.minutes, only: :create, name: "ip",
             with: -> { redirect_to new_confirmation_url, alert: t("flash.alert.try_again_later") }
  rate_limit to: 5, within: 10.minutes, only: :create, name: "email",
             by: -> { params[:email_address].to_s.strip.downcase },
             with: -> { redirect_to new_confirmation_url, alert: t("flash.alert.try_again_later") }

  def show
    user = User.find_by_token_for(:email_confirmation, params[:token])
    return redirect_to new_confirmation_path, alert: t("flash.alert.confirm_link_invalid") unless user

    user.confirm!
    Audit.record(:email_confirmed, actor: user, subject: user)
    start_new_session_for user
    redirect_to root_path, notice: t("flash.notice.email_confirmed")
  end

  def new; end

  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    if user && !user.confirmed?
      ConfirmationsMailer.confirm(user).deliver_later
      Audit.record(:confirmation_resent, actor: nil, subject: user)
    end
    # The same answer whether or not the address has an account, so this cannot confirm that one exists.
    redirect_to new_session_path, notice: t("flash.notice.confirmation_resent")
  end
end
