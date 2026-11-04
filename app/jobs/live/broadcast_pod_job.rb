# frozen_string_literal: true

module Live
  # Pushes a pod's state to the round page and, while its round is the current one, every seated
  # participant's table. The pod comes by id, or (for a result, which belongs to a participant and
  # a round, not a pod) by the round and the seated participant. refresh: also morph-refresh the
  # round page, for changes that move the pod card's staff buttons.
  class BroadcastPodJob < ApplicationJob
    PRELOAD = [:event, :judge_calls, { round: :results },
               { seatings: { event_participant: [:event, { player: :user }] } },
               { event_participants: { player: :user } }].freeze

    def perform(pod_id: nil, round_id: nil, event_participant_id: nil, refresh: false, request_id: nil)
      pod = find_pod(pod_id, round_id, event_participant_id)
      return unless pod&.round&.published?

      broadcast_state(pod)
      LiveBroadcasts.refresh_round(pod.round_id, request_id: request_id) if refresh
      broadcast_tables(pod) if current_round?(pod.round)
    end

    private

    def find_pod(pod_id, round_id, event_participant_id)
      pods = Pod.preload(*PRELOAD)
      return pods.find_by(id: pod_id) if pod_id

      pods.joins(:seatings).find_by(round_id: round_id, seatings: { event_participant_id: event_participant_id })
    end

    def broadcast_state(pod)
      LiveBroadcasts.each_locale do |locale|
        Turbo::StreamsChannel.broadcast_replace_to(
          LiveBroadcasts.round_stream(pod.round_id, locale),
          target: "pod_#{pod.id}_state", partial: "organizer/pods/state", locals: { pod: pod }
        )
      end
    end

    def broadcast_tables(pod)
      pod.seatings.each do |seating|
        LiveBroadcasts.broadcast_table(Play::TableState.new(participant: seating.event_participant,
                                                            round: pod.round, pod: pod))
      end
    end

    # "My table" shows the latest published round only: a correction to an older one changes nothing there.
    def current_round?(round)
      round.event.rounds.published.maximum(:number) == round.number
    end
  end
end
