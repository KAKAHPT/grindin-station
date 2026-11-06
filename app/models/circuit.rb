# frozen_string_literal: true

class Circuit < ApplicationRecord
  scope :for_organizer, ->(organizer) { where(event_organizer: organizer) }
  scope :featured, -> { where(featured: true) }

  has_many :events, dependent: :nullify
  has_many :tournaments, dependent: :nullify
  has_many :leagues, dependent: :nullify
  has_many :circuit_standings, dependent: :destroy
  belongs_to :event_organizer

  # The organizer's banner for the circuit, behind its card on /circuits and its page header.
  has_one_attached :banner do |attachable|
    attachable.variant :card, resize_to_fill: [800, 300]
    attachable.variant :wide, resize_to_fill: [1600, 400]
  end
  validate :banner_type_and_size

  def standings
    circuit_standings.ranked
  end

  def update_standings!
    circuit_standings.update_all(points: 0, events_count: 0)
    circuit_standings.destroy_all
  end

  private

  def banner_type_and_size
    return unless banner.attached?

    errors.add(:banner, :content_type) unless User::AVATAR_TYPES.include?(banner.blob.content_type)
    errors.add(:banner, :too_big) if banner.blob.byte_size > User::BANNER_MAX_SIZE
  end
end
