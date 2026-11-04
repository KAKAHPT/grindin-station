# frozen_string_literal: true

class Result < ApplicationRecord
  belongs_to :event_participant
  belongs_to :round
  # Set once the result is replaced by a correction to a closed round; kept for audit only.
  belongs_to :superseded_by, class_name: "Result", optional: true
  belongs_to :recorded_by, class_name: "User", foreign_key: :recorded_by_user_id, optional: true, inverse_of: false

  has_one :event, through: :round

  SELECTABLE_SUBTYPES = %w[Draw Win].freeze
  SUBTYPES = SELECTABLE_SUBTYPES + %w[Loss Penalty].freeze
  ELIMINATION_SELECTABLE_SUBYTPES = %w[Advance].freeze
  ELIMINATION_SUBYTPES = ELIMINATION_SELECTABLE_SUBYTPES + %w[Eliminated].freeze

  scope :publishable, -> { joins(:round).where.not(rounds: { finished_at: nil }) }
  scope :current, -> { where(superseded_by_id: nil) }

  # A new or changed result moves its pod to (or within) :completed: push the pod live and refresh
  # the round page, whose staff buttons depend on it. The job finds the pod; no query here.
  after_commit on: %i[create update] do
    Live::BroadcastPodJob.perform_later(round_id: round_id, event_participant_id: event_participant_id,
                                        refresh: true, request_id: Turbo.current_request_id)
  end

  validates(
    :event_participant_id,
    {
      uniqueness: { scope: :round_id, conditions: -> { current }, if: -> { superseded_by_id.nil? } }
    }
  )

  # In-place write for open rounds only; closed rounds go through Results::Apply (superseding).
  def self.create_or_update_by(**keys)
    result = Result.current.find_by(keys)
    result = Result.new(keys) if result.blank?

    yield(result)

    result.save
  end
end
