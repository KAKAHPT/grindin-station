# frozen_string_literal: true

# A user working one event in a role. The event's owner is its organizer without a row. A caster (stream
# commentator) only reads: the overview, the roster and the rounds.
class EventStaff < ApplicationRecord
  self.table_name = "event_staff"

  ROLES = %w[organizer judge scorekeeper caster].freeze

  belongs_to :event
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :event_id }
end
