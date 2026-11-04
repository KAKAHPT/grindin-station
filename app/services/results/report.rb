# frozen_string_literal: true

module Results
  # A seated player reports their pod's result. With no confirmation required it is applied at
  # once; otherwise it waits in pod.pending_result for Results::Confirm. A second report from
  # another player that matches counts as a confirmation; one that differs disputes the pod.
  # At a 1v1 event the report carries the game score (see Results::Apply) and so does the pending JSON.
  class Report
    TYPES = %w[Win Draw].freeze

    def self.call(pod:, participant:, type:, winner: nil, games: nil)
      new(pod: pod, participant: participant, type: type, winner: winner, games: games).call
    end

    def initialize(pod:, participant:, type:, winner:, games: nil)
      @pod = pod
      @participant = participant
      @type = type
      @winner = winner
      @games = games
    end

    def call
      Pod.transaction do
        @pod.lock!
        check!
        if @pod.event.result_confirmation == "none" then apply_now
        elsif @pod.pending_result.nil? then start_pending
        elsif @pod.pending_result == payload then Confirm.call(pod: @pod, participant: @participant)
        else dispute
        end
        @pod
      end
    end

    private

    def check! # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity -- one line per guard
      refuse("self_report_disabled") unless @pod.event.self_report_enabled
      refuse("not_seated") unless @pod.seated?(@participant)
      refuse("already_finished") if @pod.finished?
      refuse("disputed") if @pod.disputed?
      refuse("invalid_type") unless TYPES.include?(@type)
      refuse("draw_in_top_cut") if @type == "Draw" && @pod.round.is_a?(SingleEliminationRound)
      refuse("invalid_winner") if @type == "Win" && !@pod.seated?(@winner)
      refuse("already_confirmed") if @pod.pending_result && @pod.confirmations.key?(@participant.id)
      @score = Apply.check_games!(@pod.event, @type, @games)
    end

    def refuse(key)
      raise NotAllowed, key
    end

    def payload
      return { "type" => "Draw" }.merge(games_payload("games")) if @type == "Draw"

      { "type" => "Win", "winner_id" => @winner.id }.merge(games_payload("winner"))
    end

    def games_payload(key)
      @score ? { "games" => { key => @score } } : {}
    end

    def apply_now
      Apply.call(pod: @pod, type: @type, winner: @winner, by: nil, games: payload["games"])
      @pod.update!(reported_by_participant_id: @participant.id, reported_at: Time.current,
                   pending_result: nil, confirmations: {})
    end

    def start_pending
      now = Time.current
      @pod.update!(pending_result: payload, reported_by_participant_id: @participant.id, reported_at: now,
                   confirmations: { @participant.id => now.iso8601 })
    end

    def dispute
      @pod.update!(disputed: true)
      JudgeCalls::Open.call(event: @pod.event, pod: @pod, participant: @participant,
                            reason: "Conflicting result reports: #{conflict}")
    end

    # "seat 1 says Win by Ana; seat 3 says Draw": the pending claim first, then this one.
    def conflict
      first = @pod.event_participants.find_by(id: @pod.reported_by_participant_id)
      [claim(first, @pod.pending_result), claim(@participant, payload)].join("; ")
    end

    def claim(reporter, result)
      seat = @pod.seatings.find_by(event_participant_id: reporter&.id)&.order
      said = result["type"]
      said += " by #{@pod.event_participants.find_by(id: result['winner_id'])&.name}" if said == "Win"
      said += " #{result['games'].values.first.join('-')}" if result["games"]
      "seat #{seat || '?'} says #{said}"
    end
  end
end
