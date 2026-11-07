# frozen_string_literal: true

class ConfirmationsMailer < ApplicationMailer
  def confirm(user)
    @user = user
    mail subject: t("confirmations_mailer.confirm.subject"), to: user.email_address
  end
end
