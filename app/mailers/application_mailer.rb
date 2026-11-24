# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  # The sender: MAIL_FROM, else noreply at the site's domain.
  default from: lambda {
    ENV["MAIL_FROM"].presence || "#{I18n.t('app.name')} <noreply@#{ENV.fetch('GS_DOMAIN', 'grindin.test')}>"
  }
  layout "mailer"
end
