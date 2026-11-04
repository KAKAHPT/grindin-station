# frozen_string_literal: true

module Play
  # Public pairings of one event (/t/:slug/pairings): the tables of the latest published round, or of any
  # published round with ?round=N. Read-only; it follows the event's pairings stream (morph refresh).
  # A signed-in participant's own table comes first.
  class PairingsController < BaseController
    public_actions :show

    def show
      @rounds = current_event.rounds.published.order(:number).to_a
      @round = requested_round
      return unless @round

      load_pods
      @byes = @round.byes.preload(event_participant: { player: :user }).sort_by { |bye| bye.event_participant.name }
    end

    private

    # The round's tables in order, the signed-in participant's own table first.
    def load_pods
      pods = @round.pods.order(:number)
        .preload({ round: :results }, seatings: { event_participant: { player: :user } }).to_a
      @my_pod = own_pod(pods)
      @pods = @my_pod ? [@my_pod, *(pods - [@my_pod])] : pods
    end

    # The signed-in participant's table among the round's pods, or nil.
    def own_pod(pods)
      return unless current_participant

      pods.find { |pod| pod.seatings.any? { |seating| seating.event_participant_id == current_participant.id } }
    end

    # The latest published round, or the published round ?round=N (an unpublished or unknown one is not found).
    def requested_round
      return @rounds.last if params[:round].blank?

      @rounds.find { |round| round.number.to_s == params[:round] } || raise(ActiveRecord::RecordNotFound)
    end
  end
end
