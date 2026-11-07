# frozen_string_literal: true

# http://localhost:3000/rails/mailers/confirmations_mailer/confirm
class ConfirmationsMailerPreview < ActionMailer::Preview
  def confirm
    ConfirmationsMailer.confirm(User.first)
  end
end
