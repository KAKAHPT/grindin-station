# frozen_string_literal: true

# One audited action (written by Audit.record, never by model callbacks).
class AuditEvent < ApplicationRecord
  ACTIONS = %w[
    sign_in sign_in_failed sign_out sign_up oauth_sign_in oauth_failed
    password_reset_requested password_reset password_changed email_changed account_deleted
    identity_linked identity_unlinked
    staff_added staff_removed
    result_corrected round_undone round_closed participant_dropped event_state_changed
    infraction_added infraction_removed featured_changed tier_changed
    rate_limited
    admin_granted admin_revoked
    error_resolved data_exported
    organizer_approved organizer_declined organizer_revoked
  ].freeze

  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :event, optional: true

  validates :action, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_action, ->(action) { where(action: action) }
  scope :between, ->(from, to) { where(created_at: from..to) }
end
