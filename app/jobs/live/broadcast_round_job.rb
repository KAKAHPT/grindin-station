# frozen_string_literal: true

module Live
  # A round was published, started or closed: morph-refresh its staff pages and, on publishing,
  # push every participant their new table (a pod, or a bye).
  class BroadcastRoundJob < ApplicationJob
    def perform(round, tables: false, request_id: nil)
      LiveBroadcasts.refresh_round(round.id, request_id: request_id)
      LiveBroadcasts.refresh_pairings(round.event_id, request_id: request_id)
      LiveBroadcasts.refresh_standings(round.event_id, request_id: request_id)
      return unless tables && round.published?

      pod_of = pods_by_participant(round)
      round.event_participants.preload(:event).find_each do |participant|
        pod = pod_of[participant.id]
        LiveBroadcasts.broadcast_table(Play::TableState.new(participant: participant, round: round, pod: pod))
      end
    end

    private

    def pods_by_participant(round)
      round.pods.preload(*BroadcastPodJob::PRELOAD).each_with_object({}) do |pod, map|
        pod.seatings.each { |seating| map[seating.event_participant_id] = pod }
      end
    end
  end
end
