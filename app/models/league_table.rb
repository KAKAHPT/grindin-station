# frozen_string_literal: true

# A table of a league opened by a player. It waits for players (state waiting); the 4th one turns it into a
# pod that counts for the league (filled). A table that never fills is closed by its opener or expires.
# A filled table can be cancelled by the organizer on a player's request (the cancel_* columns).
class LeagueTable < ApplicationRecord
  STATES = %w[waiting filled closed expired cancelled].freeze
  CANCEL_STATES = %w[pending approved refused].freeze

  belongs_to :league, foreign_key: :event_id, inverse_of: :league_tables
  belongs_to :opener, class_name: "EventParticipant"
  belongs_to :pod, optional: true
  belongs_to :cancel_requested_by, class_name: "EventParticipant", optional: true
  belongs_to :cancel_decided_by, class_name: "User", optional: true
  has_many :seats, -> { order(:created_at) },
           class_name: "LeagueTableSeat", dependent: :destroy, inverse_of: :league_table
  has_many :participants, through: :seats, source: :event_participant

  validates :state, inclusion: { in: STATES }
  validates :cancel_state, inclusion: { in: CANCEL_STATES }, allow_nil: true

  scope :waiting, -> { where(state: "waiting") }
  scope :filled, -> { where(state: "filled") }
  scope :cancel_pending, -> { where(cancel_state: "pending") }

  STATES.each { |name| define_method(:"#{name}?") { state == name } }

  def expires_at = created_at + League::TABLE_WAIT

  # Still waiting on paper but past its two hours: nobody can join it, even before the job closed it.
  def overdue?(now = Time.current) = waiting? && expires_at <= now

  def cancel_pending? = cancel_state == "pending"

  # Filled and still to be settled: no result for every seat yet.
  def in_play? = filled? && pod.present? && !pod.finished?

  # Frees its players for another table.
  def release_seats!
    seats.where(active: true).update_all(active: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
