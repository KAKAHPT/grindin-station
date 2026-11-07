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

  # The sign-up link confirms the account; the e-mail change link applies the pending address.
  def show
    if (user = User.find_by_token_for(:email_confirmation, params[:token]))
      confirm_account(user)
    elsif (user = User.find_by_token_for(:email_change, params[:token]))
      apply_email_change(user)
    else
      redirect_to new_confirmation_path, alert: t("flash.alert.confirm_link_invalid")
    end
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

  private

  def confirm_account(user)
    user.confirm!
    Audit.record(:email_confirmed, actor: user, subject: user)
    start_new_session_for user
    redirect_to root_path, notice: t("flash.notice.email_confirmed")
  end

  def apply_email_change(user)
    from = user.email_address
    user.apply_email_change!
    Audit.record(:email_changed, actor: user, subject: user, from: from, to: user.email_address)
    user.sessions.destroy_all
    start_new_session_for user
    redirect_to account_path, notice: t("flash.notice.email_changed")
  rescue ActiveRecord::RecordInvalid
    redirect_to new_session_path, alert: t("flash.alert.email_change_refused")
  end
end
