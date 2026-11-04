# frozen_string_literal: true

module Live
  # Pushes one participant's table (for a judge call made without a pod, e.g. on a bye).
  class BroadcastTableJob < ApplicationJob
    def perform(event_participant_id)
      participant = EventParticipant.find_by(id: event_participant_id)
      LiveBroadcasts.broadcast_table(Play::TableState.for(participant)) if participant
    end
  end
end
