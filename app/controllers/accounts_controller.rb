# frozen_string_literal: true

# The signed-in user's own account: profile, password, linked sign-ins and deletion (anonymisation).
class AccountsController < ApplicationController
  before_action :set_user

  def show; end

  def update
    attrs = account_attributes
    if attrs.nil?
      @user.errors.add(:base, :current_password_invalid)
      render :show, status: :unprocessable_content
    elsif @user.update(attrs)
      back_to_account notice: t("accounts.flash.updated")
    else
      render :show, status: :unprocessable_content
    end
  end

  def unlink_identity
    identity = @user.identities.find(params.expect(:id))
    return back_to_account alert: t("accounts.flash.unlink_refused") unless @user.can_unlink_identity?

    identity.destroy
    back_to_account notice: t("accounts.flash.unlinked")
  end

  def destroy
    return back_to_account alert: t("accounts.flash.confirmation_mismatch") unless deletion_confirmed?

    Accounts::Anonymize.call(user: @user)
    terminate_session
    redirect_to root_path(locale: params[:locale]), notice: t("accounts.flash.deleted")
  end

  private

  def set_user
    @user = current_user
  end

  def back_to_account(**flash)
    redirect_to account_path(locale: params[:locale]), **flash
  end

  # Permitted attributes; blank password fields keep the password. Nil when a user who chose a password
  # sends a new one without the right current one (OAuth-created users have none to give).
  def account_attributes
    attrs = account_params
    return attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    return if @user.password_set && !@user.authenticate(params.dig(:user, :current_password).to_s)

    attrs.merge(password_set: true)
  end

  def account_params
    params.expect(user: %i[name email_address handle country bio visibility avatar password password_confirmation])
  end

  # The user typed the locale's delete word ("delete" / "eliminar").
  def deletion_confirmed?
    params[:confirmation].to_s.strip.casecmp?(t("accounts.show.delete_word"))
  end
end
