# frozen_string_literal: true

module Play
  # Public big-screen clock of one event (/t/:slug/timer): no login, no nav.
  class TimersController < ApplicationController
    include PublicEvent

    layout "timer"

    allow_unauthenticated_access

    def show
      @event = find_public_event!
      @round = @event.rounds.where(published: true).order(number: :desc).first
      @minutes = round_minutes
    end

    private

    def round_minutes
      return unless @round

      @round.is_a?(SingleEliminationRound) ? @event.top_cut_round_minutes : @event.round_minutes
    end
  end
end
