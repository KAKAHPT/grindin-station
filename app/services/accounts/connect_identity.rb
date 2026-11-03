# frozen_string_literal: true

module Accounts
  # Finds or links the user behind an OmniAuth sign-in: a known identity wins, then the signed-in user,
  # then an account with the same (provider-verified) e-mail, else a new user with a random password.
  class ConnectIdentity
    # The e-mail belongs to an existing account but the provider has not verified it.
    class UnverifiedEmail < StandardError; end

    # Where each provider says it verified the e-mail (raw_info from the strategy).
    VERIFIED_KEYS = { "google_oauth2" => "email_verified", "discord" => "verified" }.freeze

    def self.call(auth:, current_user: nil)
      identity = Identity.find_by(provider: auth.provider, uid: auth.uid.to_s)
      return identity.user if identity

      User.transaction do
        link(current_user || find_by_email(auth) || create_user(auth.info), auth)
      end
    end

    def self.find_by_email(auth)
      return if auth.info.email.blank?

      user = User.find_by(email_address: auth.info.email)
      raise UnverifiedEmail if user && !email_verified?(auth)

      user
    end

    def self.email_verified?(auth)
      raw = auth.dig("extra", "raw_info") || {}
      key = VERIFIED_KEYS[auth.provider]
      return raw[key] == true if key && raw.key?(key)

      auth.info.email_verified == true
    end

    def self.create_user(info)
      User.create!(email_address: info.email, name: info.name.presence || info.email.to_s.split("@").first,
                   password: SecureRandom.base58(32))
    end

    def self.link(user, auth)
      user.identities.create!(provider: auth.provider, uid: auth.uid.to_s, email: auth.info.email, name: auth.info.name)
      user
    end
    private_class_method :find_by_email, :email_verified?, :create_user, :link
  end
end
