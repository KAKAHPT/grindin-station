# frozen_string_literal: true

module Play
  # Public standings of one event (/t/:slug/standings), in the play layout.
  class StandingsController < BaseController
    public_actions :show, :player

    def show
      @tournament = current_event
      @standings = EventParticipant.standings_for(current_event)
      @standings_in_modal = false
      render "event_participants/index"
    end

    # One player's path through a finished event, loaded into the final standings' dialog (frame "player_path").
    def player
      return head(:not_found) unless current_event.finished?

      @player = EventParticipant.standings_for(current_event).find { |p| p.id == params[:participant_id] }
      return head(:not_found) unless @player&.ranked?

      @steps = PlayPlayerPath.call(current_event, @player)
      render layout: false
    end
  end
end
