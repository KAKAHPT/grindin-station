# frozen_string_literal: true

module Play
  # Public standings of one event (/t/:slug/standings), in the play layout.
  class StandingsController < BaseController
    public_actions :show

    def show
      @tournament = current_event
      @standings = EventParticipant.standings_for(current_event)
      @standings_in_modal = false
      render "event_participants/index"
    end
  end
end
