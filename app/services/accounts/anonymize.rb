# frozen_string_literal: true

module Accounts
  # Account deletion: strips the user's personal data but keeps the row, so its player, event
  # participations and results stay intact (and keep their key) under the name "Removed player".
  class Anonymize
    def self.call(user:)
      User.transaction do
        user.identities.destroy_all
        user.sessions.destroy_all
        user.avatar.purge_later if user.avatar.attached?
        user.update!(removed_attributes)
      end
      user
    end

    def self.removed_attributes
      { name: "Removed player", email_address: "deleted-#{SecureRandom.uuid}@removed.invalid",
        password: SecureRandom.base58(32), password_set: false, handle: nil, bio: nil, country: nil,
        anonymized_at: Time.current }
    end
    private_class_method :removed_attributes
  end
end
