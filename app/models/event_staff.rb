# frozen_string_literal: true

# A user working one event in a role. The event's owner is its organizer without a row.
# organizer and judge: everything on the event (Settings and Staff stay with the owner/organizer);
# scorekeeper: rounds (publish, start, close), results, check-in and payment, no adding or dropping players;
# caster (stream commentator): read-only on the overview, the roster and the rounds.
class EventStaff < ApplicationRecord
  self.table_name = "event_staff"

  ROLES = %w[organizer judge scorekeeper caster].freeze

  belongs_to :event
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :event_id }
end
