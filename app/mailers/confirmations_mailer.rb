# frozen_string_literal: true

class ConfirmationsMailer < ApplicationMailer
  def confirm(user)
    @user = user
    mail subject: t("confirmations_mailer.confirm.subject"), to: user.email_address
  end

  # To the new address of a pending e-mail change.
  def change(user)
    @user = user
    mail subject: t("confirmations_mailer.change.subject"), to: user.unconfirmed_email
  end
end
