# frozen_string_literal: true

class Player < ApplicationRecord
  belongs_to :user, optional: true

  has_many :event_participations, class_name: "EventParticipant", dependent: :destroy
  has_many :events, through: :event_participations
  has_many :infractions, dependent: :destroy

  normalizes :wizards_email, with: ->(e) { e.strip.downcase.presence }

  validates :key, presence: true
  validates :wizards_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  def name
    user&.display_name || "Anonymous ##{key&.first(4)}"
  end

  # Where stores report this player's results on Wizards EventLink: their own Wizards e-mail, else the sign-in one.
  def reporting_email
    wizards_email.presence || user&.email_address
  end

  def participant?(event)
    event_participations.any? { |ep| ep.event_id == event.id }
  end

  def participant(event)
    event_participations.find { |ep| ep.event_id == event.id }
  end
end
