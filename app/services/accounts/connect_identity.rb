# frozen_string_literal: true

module Accounts
  # Finds or links the user behind an OmniAuth sign-in: a known identity wins, then the signed-in user,
  # then an account with the same e-mail, else a new user with a random password.
  class ConnectIdentity
    def self.call(auth:, current_user: nil)
      identity = Identity.find_by(provider: auth.provider, uid: auth.uid.to_s)
      return identity.user if identity

      User.transaction do
        user = current_user || find_by_email(auth.info.email) || create_user(auth.info)
        link(user, auth)
      end
    end

    def self.link(user, auth)
      user.identities.create!(provider: auth.provider, uid: auth.uid.to_s, email: auth.info.email, name: auth.info.name)
      user
    end

    def self.find_by_email(email)
      User.find_by(email_address: email) if email.present?
    end

    def self.create_user(info)
      User.create!(email_address: info.email, name: info.name.presence || info.email.to_s.split("@").first,
                   password: SecureRandom.base58(32))
    end
    private_class_method :link, :find_by_email, :create_user
  end
end
