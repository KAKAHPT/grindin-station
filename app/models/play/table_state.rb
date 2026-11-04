# frozen_string_literal: true

module Play
  # What "my table" shows a participant: their pod in the latest published round (or a bye, or
  # nothing yet) and what they may do with its result. Used by the page and by its live broadcasts.
  class TableState
    attr_reader :participant, :round, :pod

    delegate :event, to: :participant

    def self.for(participant)
      round = participant.event.rounds.published.order(number: :desc).first
      pod = round && round.pods.joins(:seatings).find_by(seatings: { event_participant_id: participant.id })
      new(participant: participant, round: round, pod: pod)
    end

    def initialize(participant:, round:, pod:)
      @participant = participant
      @round = round
      @pod = pod
    end

    # Locals of play/tables/_table.
    def locals
      { event: event, participant: participant, round: round, pod: pod, seat: seat, seatings: seatings,
        status: status, can_report: can_report?, can_confirm: can_confirm?, can_contest: can_contest?,
        judge_called: judge_called? }
    end

    def seatings
      return [] unless pod

      @seatings ||=
        if pod.association(:seatings).loaded? then pod.seatings
        else pod.seatings.includes(event_participant: { player: :user })
        end
    end

    def seat
      seatings.find { |s| s.event_participant_id == participant.id }&.order
    end

    def status
      @status ||= pod&.report_status
    end

    def can_report?
      self_report? && status == :playing
    end

    def can_confirm?
      self_report? && %i[pending review].include?(status) && !pod.confirmations.key?(participant.id) &&
        pod.reported_by_participant_id != participant.id
    end

    def can_contest?
      self_report? && %i[pending review completed].include?(status)
    end

    # An open or acknowledged call already stands for the pod (or, without one, for the player).
    def judge_called?
      return pod.open_judge_call? if pod

      JudgeCall.open_or_acknowledged.exists?(event: event, participant: participant, pod: nil)
    end

    private

    def self_report?
      pod.present? && event.self_report_enabled
    end
  end
end
