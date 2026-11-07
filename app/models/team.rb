# frozen_string_literal: true

# A team of players (the rankings' Teams tab counts its five best contributions). Created by a player, who owns
# it: accepts join requests and invites players, up to MAX_MEMBERS accepted members.
class Team < ApplicationRecord
  MAX_MEMBERS = 5

  belongs_to :owner, class_name: "User", optional: true
  has_many :memberships, class_name: "TeamMembership", dependent: :destroy
  has_many :members, -> { merge(TeamMembership.accepted) }, through: :memberships, source: :user

  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }
  validates :name, presence: true, length: { maximum: 30 }, uniqueness: { case_sensitive: false }

  def full? = members.count >= MAX_MEMBERS

  def owned_by?(user) = owner_id.present? && owner_id == user.id

  # The owner leaves or is removed: the oldest remaining member takes over, or the team goes with its last member.
  def hand_over!
    successor = memberships.accepted.where.not(user_id: owner_id).order(:created_at).first
    successor ? update!(owner: successor.user) : destroy!
  end
end
