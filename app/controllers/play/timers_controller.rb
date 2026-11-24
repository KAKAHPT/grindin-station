# frozen_string_literal: true

module Play
  # Public big-screen pages of one event, no login and no nav: the plain clock (/t/:slug/timer) and the
  # screen with the clock, the results and the tables (/t/:slug/screen).
  class TimersController < ApplicationController
    include PublicEvent

    layout "timer"

    allow_unauthenticated_access

    def show
      @event = find_public_event!
      @round = @event.rounds.where(published: true).order(number: :desc).first
      @minutes = round_minutes
    end

    # The big screen for a TV or a second monitor (/t/:slug/screen): the clock, a summary of the results as
    # they come in, and the round's tables in blocks that take turns.
    def screen
      @event = find_public_event!
      @round = @event.rounds.where(published: true).order(number: :desc).first
      @minutes = round_minutes
      @pods = screen_pods
      render layout: "screen"
    end

    private

    def screen_pods
      return [] unless @round

      @round.pods.order(:number).preload({ round: :results }, seatings: { event_participant: { player: :user } }).to_a
    end

    def round_minutes
      return unless @round

      @round.is_a?(SingleEliminationRound) ? @event.top_cut_round_minutes : @event.round_minutes
    end
  end
end
