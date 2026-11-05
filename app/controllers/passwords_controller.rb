# frozen_string_literal: true

class PasswordsController < ApplicationController
  allow_unauthenticated_access
  layout "auth"
  before_action :set_user_by_token, only: %i[edit update]
  # Per address loosely (a venue's players share one), per e-mail tightly.
  rate_limit to: 20, within: 10.minutes, only: :create, name: "ip",
             with: -> { redirect_to new_password_url, alert: t("flash.alert.try_again_later") }
  rate_limit to: 5, within: 10.minutes, only: :create, name: "email",
             by: -> { params[:email_address].to_s.strip.downcase },
             with: -> { redirect_to new_password_url, alert: t("flash.alert.try_again_later") }

  def new; end

  def edit; end

  def create
    if (user = User.find_by(email_address: params[:email_address]))
      PasswordsMailer.reset(user).deliver_later
    end
    Audit.record(:password_reset_requested, actor: nil, subject: user,
                                            email: params[:email_address].to_s.strip.downcase)

    redirect_to new_session_path, notice: t("flash.notice.password_reset_sent")
  end

  def update
    if reset_password
      @user.sessions.destroy_all
      Audit.record(:password_reset, actor: @user, subject: @user)
      redirect_to new_session_path, notice: t("flash.notice.password_reset")
    else
      redirect_to edit_password_path(params[:token]), alert: t(reset_failure_key)
    end
  end

  private

  # has_secure_password ignores a blank password, which would "succeed" without changing it.
  def reset_password
    params[:password].present? &&
      @user.update(params.permit(:password, :password_confirmation).merge(password_set: true))
  end

  def reset_failure_key
    params[:password].to_s.length < 8 ? "flash.alert.password_too_short" : "flash.alert.passwords_no_match"
  end

  def set_user_by_token
    @user = User.find_by_token_for!(:password_reset, params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to new_password_path, alert: t("flash.alert.password_reset_link_invalid")
  end
end
