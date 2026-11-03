# frozen_string_literal: true

module Play
  # A player calls a judge, for their current pod when they have one.
  class JudgeCallsController < BaseController
    def create
      reason = params[:reason].presence || "Judge requested"
      JudgeCalls::Open.call(event: current_event, pod: current_pod, participant: current_participant, reason: reason)
      redirect_to my_table_path, notice: t("play.notices.judge_called")
    end
  end
end
