# frozen_string_literal: true

module Organizer
  class ResultsController < OrganizerController
    allow_roles :organizer, :judge, :scorekeeper

    def new
      @tournament = load_tournament
      @round = load_round(@tournament)
      @pod = load_pod(@round)
      @result = Result.new(round: @round)
      @warning = correction_warning
    end

    def create
      @tournament = load_tournament
      @round = load_round(@tournament)
      @pod = load_pod(@round)
      event_participant = load_participant(@pod) if result_params[:event_participant_id].present?
      return render_confirmation if unconfirmed_correction?

      submit(event_participant)
      redirect_to [:organizer, @tournament, @round.becomes(Round)], notice: t("flash.notice.result_submitted")
    rescue StandardError => e
      redirect_to [:organizer, @tournament, @round.becomes(Round)], alert: e
    end

    private

    def submit(event_participant)
      Events::SubmitResultJob.perform_now(
        type: result_params[:type],
        event_participant: event_participant, round: @round, pod: @pod, by: current_user
      )
    end

    # Correcting a closed round once a later round is out needs an explicit confirm.
    def correction_warning
      Results::Apply.warning_for(@pod) if @round.finished_at.present?
    end

    def unconfirmed_correction?
      correction_warning.present? && params[:confirm] != "1"
    end

    def render_confirmation
      # Plain Result (not the STI subclass) so the form keeps posting to the results route.
      @result = Result.new(round: @round)
      @result.assign_attributes(type: result_params[:type], event_participant_id: result_params[:event_participant_id])
      @warning = correction_warning
      render :new, status: :unprocessable_content
    end

    def load_tournament
      Tournament.staffed_by(current_user).find params[:tournament_id]
    end

    def load_round(tournament)
      tournament.rounds.find params[:round_id]
    end

    def load_pod(round)
      round.pods.find params[:pod_id]
    end

    def load_participant(pod)
      pod.event_participants.find result_params[:event_participant_id]
    end

    def result_params
      params.expect(result: [
                      :type,
                      :event_participant_id
                    ])
    end
  end
end
