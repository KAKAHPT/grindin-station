# frozen_string_literal: true

module Play
  # "My table": the participant's pod in the current round and what they can do with its result.
  class TablesController < BaseController
    def show
      return render(:waiting) unless current_round

      @pod = current_pod
      return render(:bye) unless @pod

      load_table
    end

    private

    def load_table # rubocop:disable Metrics/AbcSize -- one line per flag
      @seatings = @pod.seatings.includes(event_participant: { player: :user })
      @seat = @seatings.find { |s| s.event_participant_id == current_participant.id }.order
      @status = @pod.report_status
      @can_report = current_event.self_report_enabled && @status == :playing
      @can_confirm = current_event.self_report_enabled && %i[pending review].include?(@status) &&
                     !@pod.confirmations.key?(current_participant.id) &&
                     @pod.reported_by_participant_id != current_participant.id
      @can_contest = current_event.self_report_enabled && %i[pending review completed].include?(@status)
    end
  end
end
