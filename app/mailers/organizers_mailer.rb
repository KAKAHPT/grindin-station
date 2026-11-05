# frozen_string_literal: true

# Sent when an admin approves a waiting-list signup (M13 D17).
class OrganizersMailer < ApplicationMailer
  def approved(user)
    @user = user
    mail subject: t("organizers_mailer.approved.subject"), to: user.email_address
  end
end
