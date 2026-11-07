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
      credentials_saved
      back_to_account notice: t("accounts.flash.updated")
    else
      render :show, status: :unprocessable_content
    end
  end

  def unlink_identity
    identity = @user.identities.find(params.expect(:id))
    return back_to_account alert: t("accounts.flash.unlink_refused") unless @user.can_unlink_identity?

    identity.destroy
    Audit.record(:identity_unlinked, subject: identity, provider: identity.provider)
    back_to_account notice: t("accounts.flash.unlinked")
  end

  def destroy
    return back_to_account alert: t("accounts.flash.confirmation_mismatch") unless deletion_confirmed?

    Audit.record(:account_deleted, subject: @user)
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
  # changes it or the e-mail without the right current one (OAuth-created users have none to give).
  def account_attributes
    attrs = account_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    return if current_password_needed?(attrs) && !@user.authenticate(params.dig(:user, :current_password).to_s)

    attrs[:password].present? ? attrs.merge(password_set: true) : attrs
  end

  def current_password_needed?(attrs)
    email_changes = attrs.key?(:email_address) &&
                    User.normalize_value_for(:email_address, attrs[:email_address].to_s) != @user.email_address
    @user.password_set && (attrs[:password].present? || email_changes)
  end

  def credentials_saved
    end_other_sessions if @user.saved_change_to_password_digest? || @user.saved_change_to_email_address?
    audit_credential_changes
  end

  # Only the fact of a new password; the e-mail change with both addresses.
  def audit_credential_changes
    Audit.record(:password_changed, subject: @user) if @user.saved_change_to_password_digest?
    return unless @user.saved_change_to_email_address?

    from, to = @user.saved_change_to_email_address
    Audit.record(:email_changed, subject: @user, from: from, to: to)
  end

  # A new password or e-mail signs out every other device.
  def end_other_sessions
    @user.sessions.where.not(id: Current.session.id).destroy_all
  end

  def account_params
    params.expect(user: [:name, :email_address, :handle, :country, :bio, :visibility, :feed_scope, :avatar,
                         :banner, :password, :password_confirmation, { player_attributes: [:wizards_email] }])
  end

  # The user typed the locale's delete word ("delete" / "eliminar").
  def deletion_confirmed?
    params[:confirmation].to_s.strip.casecmp?(t("accounts.show.delete_word"))
  end
end
