# frozen_string_literal: true

module Organizer
  class PodsController < OrganizerController
    EXTRA_TIME_STEP = 5

    allow_roles :organizer, :judge, :scorekeeper, only: :extra_time

    # +5 minutes for one table; shown on its card (the round timer stays per round).
    def extra_time
      round = load_round
      pod = round.pods.find params.expect(:id)
      pod.increment!(:extra_time, EXTRA_TIME_STEP) # rubocop:disable Rails/SkipsModelValidations
      redirect_to [:organizer, round.event, round.becomes(Round)],
                  notice: t("rounds.extra_time_added", table: pod.number)
    end

    private

    def load_round
      Tournament.staffed_by(current_user).find(params.expect(:tournament_id)).rounds.find(params.expect(:round_id))
    end
  end
end
