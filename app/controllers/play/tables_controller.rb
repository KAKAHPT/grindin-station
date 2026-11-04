# frozen_string_literal: true

module Play
  # "My table": the participant's pod in the current round and what they can do with its result.
  # The page follows the participant's live stream, so it changes without a reload.
  class TablesController < BaseController
    def show
      @table = TableState.new(participant: current_participant, round: current_round, pod: current_pod)
    end
  end
end
