# frozen_string_literal: true

module Play
  # Player-facing pages of one event (/t/:slug): only an enrolled, not eliminated participant gets in,
  # except for the actions declared with `public_actions`, open to anyone (current_participant may be nil).
  class BaseController < ApplicationController
    layout "play"

    before_action :load_event
    before_action :load_participant

    # Open to visitors: no login, no participant required (the signed-in user's participant is still loaded).
    def self.public_actions(*actions)
      allow_unauthenticated_access(only: actions)
      skip_before_action :load_participant, only: actions
      before_action :find_participant, only: actions
    end

    helper_method :current_participant, :current_event, :current_round, :judge_called?

    rescue_from Results::NotAllowed do |e|
      redirect_to my_table_path, alert: t("results.not_allowed.#{e.message}")
    end

    private

    attr_reader :current_participant, :current_event

    def load_event
      @current_event = Tournament.find_by!(slug: params.expect(:slug))
    end

    def load_participant
      find_participant
      return if @current_participant&.enrolled? && !eliminated?

      redirect_to play_event_path(current_event.slug, locale: params[:locale]), alert: t("play.not_a_participant")
    end

    # The signed-in user's participant in the event, in any state, or nil.
    def find_participant
      player = current_user&.player
      @current_participant = player && current_event.event_participants.find_by(player: player)
    end

    def eliminated?
      current_participant.all_results.exists?(type: "Eliminated", superseded_by_id: nil)
    end

    # The latest published round, or nil before pairings are out.
    def current_round
      @current_round ||= current_event.rounds.where(published: true).order(number: :desc).first
    end

    # The participant's pod in the current round, or nil (no round yet, or a bye).
    def current_pod
      return unless current_round

      @current_pod ||= current_round.pods.joins(:seatings)
        .find_by(seatings: { event_participant_id: current_participant.id })
    end

    # An open or acknowledged call already stands for the current pod (or, without one, for the player).
    def judge_called?
      return current_pod.open_judge_call? if current_pod

      JudgeCall.open_or_acknowledged.exists?(event: current_event, participant: current_participant, pod: nil)
    end

    def my_table_path
      play_me_path(current_event.slug, locale: params[:locale])
    end

    # A pod from the URL, only when it is the participant's own pod this round.
    def requested_pod
      pod = current_pod
      raise ActiveRecord::RecordNotFound unless pod && pod.id == params[:pod_id]

      pod
    end
  end
end
