# frozen_string_literal: true

module Play
  # Public pairings of one event (/t/:slug/pairings): the tables of the latest published round, or of any
  # published round with ?round=N. Read-only; it follows no live stream (the page is correct on reload).
  class PairingsController < BaseController
    public_actions :show

    def show
      @rounds = current_event.rounds.published.order(:number).to_a
      @round = requested_round
      return unless @round

      @pods = @round.pods.order(:number)
        .preload({ round: :results }, seatings: { event_participant: { player: :user } })
      @byes = @round.byes.preload(event_participant: { player: :user }).sort_by { |bye| bye.event_participant.name }
    end

    private

    # The latest published round, or the published round ?round=N (an unpublished or unknown one is not found).
    def requested_round
      return @rounds.last if params[:round].blank?

      @rounds.find { |round| round.number.to_s == params[:round] } || raise(ActiveRecord::RecordNotFound)
    end
  end
end
