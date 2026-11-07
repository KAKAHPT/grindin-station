# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  layout "auth"
  rate_limit to: 30, within: 3.minutes, only: :create, with: lambda {
    redirect_to new_registration_url, alert: t("flash.alert.try_again_later")
  }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.merge(needs_confirmation: true))

    if @user.save
      # No session yet: the account opens when the confirmation link in the mail is clicked.
      ConfirmationsMailer.confirm(@user).deliver_later
      Audit.record(:sign_up, actor: @user, subject: @user)
      redirect_to new_session_path, notice: t("flash.notice.confirm_email_sent")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    # Organizing is by invitation: the organizer role comes from Admin::OrganizersController#approve, never from here.
    params.expect(user: [:name, :email_address, :password, :password_confirmation])
  end
end
