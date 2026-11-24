# frozen_string_literal: true

# An organizer's invitation of one account to an invitation-only event (Event#invitation_only): the invited
# user may register themselves; everyone else is refused (Registrations::Enroll).
class EventInvitation < ApplicationRecord
  belongs_to :event
  belongs_to :user
  belongs_to :invited_by, class_name: "User", optional: true

  validates :user_id, uniqueness: { scope: :event_id }
end
