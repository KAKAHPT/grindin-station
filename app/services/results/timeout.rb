# frozen_string_literal: true

module Results
  # "Time called" on a top-cut table, resolved by the event's top_cut_timeout_rule: the highest
  # seed advances (the other seats are eliminated), or the table replays with half the round
  # time added and staff review requested.
  class Timeout
    def self.call(pod:, by: nil)
      new(pod: pod, by: by).call
    end

    def initialize(pod:, by:)
      @pod = pod
      @by = by
    end

    def call
      raise ArgumentError, "time called only applies to top-cut tables" unless @pod.round.is_a?(SingleEliminationRound)

      Pod.transaction do
        @pod.lock!
        raise NotAllowed, "already_finished" if @pod.finished?

        event.top_cut_timeout_rule == "replay" ? replay : advance_highest_seed
        @pod
      end
    end

    private

    def event
      @pod.event
    end

    def advance_highest_seed
      ranked = EventParticipant.standings_for(event).index_by(&:id)
      seated = @pod.seatings.sort_by(&:order).map { |seating| ranked.fetch(seating.event_participant_id) }
      winner = seated.each_with_index.min_by { |participant, i| [-participant.rank_score, i] }.first
      Apply.call(pod: @pod, type: "Advance", winner: winner, by: @by, games: Apply::UNSCORED)
    end

    # Once per table: a pod already waiting for staff review gets no more time.
    def replay
      raise NotAllowed, "time_already_called" if @pod.review_requested_at.present?

      @pod.update!(extra_time: @pod.extra_time + (event.top_cut_round_minutes / 2), review_requested_at: Time.current)
    end
  end
end
