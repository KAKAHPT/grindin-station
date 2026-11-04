# frozen_string_literal: true

module Accounts
  # Finds or links the user behind an OmniAuth sign-in. A known identity signs its owner in; a signed-in
  # user links the identity to themselves; otherwise a provider-verified e-mail that no account uses
  # creates a new user with a random password. Local e-mails are never verified, so an e-mail match
  # never auto-links: the owner signs in with the password and links from the account page.
  class ConnectIdentity
    # The provider has not verified the e-mail, so it cannot create an account.
    class UnverifiedEmail < StandardError; end
    # An account already uses this e-mail; it must sign in with its password and link from Account.
    class EmailTaken < StandardError; end
    # A signed-in user tried to link an identity that belongs to another user.
    class IdentityTaken < StandardError; end

    # Where each provider says it verified the e-mail (raw_info from the strategy).
    VERIFIED_KEYS = { "google_oauth2" => "email_verified", "discord" => "verified" }.freeze

    def self.call(auth:, current_user: nil)
      identity = Identity.find_by(provider: auth.provider, uid: auth.uid.to_s)
      return claimed(identity, current_user) if identity
      return link(current_user, auth) if current_user

      ensure_new_account!(auth)
      User.transaction { link(create_user(auth.info), auth) }
    end

    # Only a provider-verified e-mail that no account uses may create a user.
    def self.ensure_new_account!(auth)
      raise UnverifiedEmail unless email_verified?(auth)
      raise EmailTaken if auth.info.email.present? && User.exists?(email_address: auth.info.email)
    end

    def self.claimed(identity, current_user)
      raise IdentityTaken if current_user && identity.user_id != current_user.id

      identity.user
    end

    def self.email_verified?(auth)
      raw = auth.dig("extra", "raw_info") || {}
      key = VERIFIED_KEYS[auth.provider]
      return raw[key] == true if key && raw.key?(key)

      auth.info.email_verified == true
    end

    def self.create_user(info)
      User.create!(email_address: info.email, name: info.name.presence || info.email.to_s.split("@").first,
                   password: SecureRandom.base58(32), password_set: false)
    end

    def self.link(user, auth)
      user.identities.create!(provider: auth.provider, uid: auth.uid.to_s, email: auth.info.email, name: auth.info.name)
      user
    end
    private_class_method :claimed, :ensure_new_account!, :email_verified?, :create_user, :link
  end
end
