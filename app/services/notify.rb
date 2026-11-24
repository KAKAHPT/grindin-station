# frozen_string_literal: true

# Creates in-app notifications; each method returns the rows it created.
module Notify
  STAFF_ROLES = %w[organizer judge].freeze

  extend self

  # The event's owner plus its staff organizers and judges, once each.
  def staff(event, kind:, subject:)
    user_ids = event.event_staff.where(role: STAFF_ROLES).pluck(:user_id)
    user_ids << event.event_organizer.user_id
    create_for(user_ids, kind: kind, subject: subject)
  end

  # Every user seated in the pod.
  def participants(pod, kind:, subject:)
    create_for(pod.users.pluck(:id), kind: kind, subject: subject)
  end

  # Every user playing the round: seated at a table or sitting it out with a bye (guests have no account).
  def round(round, kind:)
    participant_ids = round.seatings.pluck(:event_participant_id) + round.byes.pluck(:event_participant_id)
    user_ids = EventParticipant.where(id: participant_ids).joins(:player).pluck("players.user_id")
    create_for(user_ids, kind: kind, subject: round)
  end

  def create_for(user_ids, kind:, subject:)
    User.where(id: user_ids.compact.uniq).map { |user| Notification.create!(user: user, kind: kind, subject: subject) }
  end
end
