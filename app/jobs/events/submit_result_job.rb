# frozen_string_literal: true

module Events
  class SubmitResultJob < ApplicationJob
    # Returns the Results::Apply::Outcome.
    def perform(type:, event_participant:, round:, pod:, by: nil)
      outcome = Results::Apply.call(pod: pod, type: type, winner: event_participant, by: by)

      recalculate_league_scores(round) if round.event.is_a?(League) && round.event.play?
      outcome
    end

    def recalculate_league_scores(round)
      Scoring::PointWager.new(round.event).recalculate_all!
    end
  end
end
