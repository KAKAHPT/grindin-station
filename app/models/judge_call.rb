# frozen_string_literal: true

# A call for a judge, from a table (pod) or a player, worked from the Judge Center.
class JudgeCall < ApplicationRecord
  STATUSES = %w[open acknowledged closed].freeze
  REASON_MAX_LENGTH = 500

  belongs_to :event
  belongs_to :pod, optional: true
  belongs_to :participant, class_name: "EventParticipant", foreign_key: :event_participant_id,
                           optional: true, inverse_of: false
  belongs_to :acknowledged_by, class_name: "User", foreign_key: :acknowledged_by_user_id,
                               optional: true, inverse_of: false

  scope :open_or_acknowledged, -> { where(status: %w[open acknowledged]) }
  scope :closed, -> { where(status: "closed") }

  validates :reason, presence: true, length: { maximum: REASON_MAX_LENGTH }
  validates :status, inclusion: { in: STATUSES }
  validate :stays_closed, if: -> { status_in_database == "closed" && has_changes_to_save? }
  validate :acknowledged_from_open, if: -> { acknowledged? && will_save_change_to_acknowledged_at? }

  # A call shows on the table (and the pod card when it has a pod).
  after_commit on: %i[create update] do
    if pod_id then Live::BroadcastPodJob.perform_later(pod_id: pod_id, pairings: false)
    elsif event_participant_id then Live::BroadcastTableJob.perform_later(event_participant_id)
    end
  end

  STATUSES.each { |status| define_method(:"#{status}?") { self.status == status } }

  def acknowledge!(by:)
    update!(status: "acknowledged", acknowledged_by: by, acknowledged_at: Time.current)
  end

  # Allowed from open too; whoever closes an unacknowledged call is recorded as handling it.
  def close!(by:)
    update!(status: "closed", closed_at: Time.current,
            acknowledged_by: acknowledged_by || by, acknowledged_at: acknowledged_at || Time.current)
  end

  private

  # Only an open call can be acknowledged (not a second time).
  def acknowledged_from_open
    errors.add(:status, :invalid) unless status_in_database == "open"
  end

  # A closed call is final: no reopening, no second close.
  def stays_closed
    errors.add(:status, :invalid)
  end
end
