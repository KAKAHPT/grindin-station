# frozen_string_literal: true

module Organizer
  # The Judge Center: open and acknowledged calls for one event, worked by its organizers and judges.
  class JudgeCallsController < OrganizerController
    allow_roles :organizer, :judge

    CLOSED_SHOWN = 20

    def index
      @tournament = load_tournament
      calls = @tournament.judge_calls.includes(:pod, participant: :player).order(created_at: :desc)
      @active_calls = calls.open_or_acknowledged
      @closed_calls = calls.closed.limit(CLOSED_SHOWN)
    end

    def acknowledge
      transition(:acknowledge!, "flash.notice.judge_call_acknowledged")
    end

    def close
      transition(:close!, "flash.notice.judge_call_closed")
    end

    private

    def transition(event, notice)
      call = load_call
      return redirect_to(judge_center_path, alert: t("flash.alert.judge_call_closed")) if call.closed?

      call.public_send(event, by: current_user)
      redirect_to judge_center_path, notice: t(notice)
    end

    def load_call
      load_tournament.judge_calls.find(params.expect(:id))
    end

    def load_tournament
      @load_tournament ||= Tournament.staffed_by(current_user).find(params.expect(:tournament_id))
    end

    def judge_center_path
      organizer_tournament_judge_calls_path(params.expect(:tournament_id))
    end
  end
end
