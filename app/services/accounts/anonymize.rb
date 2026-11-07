# frozen_string_literal: true

module Accounts
  # Account deletion: strips the user's personal data but keeps the row, so its player, event
  # participations and results stay intact (and keep their key) under the name "Removed player".
  class Anonymize
    def self.call(user:)
      User.transaction do
        user.identities.destroy_all
        user.sessions.destroy_all
        purge_images(user)
        leave_teams(user)
        user.update!(removed_attributes)
        # A fresh key, so nothing links the removed player to its old identity.
        user.player&.update!(wizards_email: nil, key: "removed-#{SecureRandom.hex(12)}")
      end
      user
    end

    # Owned teams pass to their oldest member (or go with their last one); memberships go with the user.
    def self.leave_teams(user)
      user.owned_teams.find_each(&:hand_over!)
      user.team_memberships.destroy_all
    end
    private_class_method :leave_teams

    def self.purge_images(user)
      user.avatar.purge_later if user.avatar.attached?
      user.banner.purge_later if user.banner.attached?
    end
    private_class_method :purge_images

    def self.removed_attributes
      { name: "Removed player", email_address: "deleted-#{SecureRandom.uuid}@removed.invalid",
        password: SecureRandom.base58(32), password_set: false, admin: false, handle: nil, bio: nil, country: nil,
        team: nil, anonymized_at: Time.current }
    end
    private_class_method :removed_attributes
  end
end
