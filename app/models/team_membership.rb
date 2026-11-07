# frozen_string_literal: true

# One player's place in a team: requested (the player asked to join, the owner accepts), invited (the owner added
# the player, the player accepts) or accepted. A player has one accepted team at a time; accepting writes the
# team's name on users.team, which the rankings and the profile tag read.
class TeamMembership < ApplicationRecord
  STATUSES = %w[requested invited accepted].freeze

  belongs_to :team
  belongs_to :user

  scope :accepted, -> { where(status: "accepted") }
  scope :pending, -> { where.not(status: "accepted") }

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :team_id }
  validate :one_accepted_team, if: :accepted?
  validate :room_in_team, if: :accepted?

  after_destroy :clear_team_name, if: :accepted?
  after_save :write_team_name, if: :accepted?

  def accepted? = status == "accepted"

  private

  def one_accepted_team
    return unless TeamMembership.accepted.where(user_id: user_id).where.not(id: id).exists?

    errors.add(:base, :already_in_a_team)
  end

  def room_in_team
    return if persisted? && status_was == "accepted"
    return unless team&.full?

    errors.add(:base, :team_full, count: Team::MAX_MEMBERS)
  end

  def write_team_name
    user.update_column(:team, team.name) # rubocop:disable Rails/SkipsModelValidations -- a denormalised copy
  end

  def clear_team_name
    return unless user.team == team.name

    user.update_column(:team, nil) # rubocop:disable Rails/SkipsModelValidations -- a denormalised copy
  end
end
