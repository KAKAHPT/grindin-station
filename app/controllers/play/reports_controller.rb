# frozen_string_literal: true

module Play
  # A player reports, confirms or contests their own pod's result (Results services do the checks).
  class ReportsController < BaseController
    before_action :load_pod

    def new
      @seatings = @pod.seatings.includes(event_participant: { player: :user })
    end

    def create
      winner = @pod.event_participants.find_by(id: params[:winner_id]) if params[:type] == "Win"
      Results::Report.call(pod: @pod, participant: current_participant, type: params[:type], winner: winner,
                           games: reported_games)
      redirect_to my_table_path, notice: t("play.notices.reported")
    end

    def confirm
      Results::Confirm.call(pod: @pod, participant: current_participant)
      redirect_to my_table_path, notice: t("play.notices.confirmed")
    end

    def contest
      Results::Contest.call(pod: @pod, participant: current_participant, reason: params[:reason])
      redirect_to my_table_path, notice: t("play.notices.contested")
    end

    private

    def load_pod
      @pod = requested_pod
    end

    # 1v1: the "won-lost-drawn" score radio or draw button ("2-1-0").
    def reported_games
      Results::Apply.games_param(params[:type], params[:games])
    end
  end
end
