# frozen_string_literal: true

# One person following another (a player, or an organizer through their account).
class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :followed, class_name: "User"

  validates :followed_id, uniqueness: { scope: :follower_id }
  validate { errors.add(:followed, :yourself) if follower_id == followed_id }
end
