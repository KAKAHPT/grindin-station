# frozen_string_literal: true

module Play
  # A player calls a judge, for their current pod when they have one. A standing call is not repeated.
  class JudgeCallsController < BaseController
    def create
      unless judge_called?
        reason = params[:reason].presence || t("play.judge_requested")
        JudgeCalls::Open.call(event: current_event, pod: current_pod, participant: current_participant,
                              reason: reason)
      end
      redirect_to my_table_path, notice: t("play.notices.judge_called")
    end
  end
end
