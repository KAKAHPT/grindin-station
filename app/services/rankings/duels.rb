# frozen_string_literal: true

module Rankings
  # The Elo duels of a pod (spec M13 D5): every pair of seated players with a current Win, Draw or
  # Loss (a Penalty is a Loss) is one duel [a_player_id, b_player_id, score_a], in seat order. The
  # better result scores 1, equal results 0.5: the winner beats everyone, the others draw among
  # themselves, an all-Draw pod is all draws, a 1v1 match is one duel. Advance (byes, cut winners),
  # Eliminated and missing results are not games. Single-elimination (cut) pods are never rated,
  # whatever results they hold (ruling R6).
  module Duels
    extend self

    RANKS = { "Win" => 2, "Draw" => 1, "Loss" => 0, "Penalty" => 0 }.freeze

    def for_pod(pod)
      return [] if pod.round.is_a?(SingleEliminationRound)

      ranked(pod).combination(2).map { |(a, rank_a), (b, rank_b)| [a, b, score(rank_a, rank_b)] }
    end

    # One list of duels per pod, by round number then pod number, cut rounds left out, in a fixed
    # number of queries.
    def for_event(event)
      rounds = event.rounds.where.not(type: "SingleEliminationRound").order(:number)
        .preload(:results, pods: { seatings: :event_participant })
      rounds.flat_map { |round| round.pods.sort_by(&:number).map { |pod| for_pod(pod) } }
    end

    private

    # [player_id, rank] of the seated players with a rated result, in seat order.
    def ranked(pod)
      results = pod.current_results.index_by(&:event_participant_id)
      pod.seatings.filter_map do |seating|
        rank = RANKS[results[seating.event_participant_id]&.type]
        player_id = seating.event_participant.player_id
        [player_id, rank] if rank && player_id
      end
    end

    def score(rank_a, rank_b) = { 1 => 1, 0 => 0.5, -1 => 0 }.fetch(rank_a <=> rank_b)
  end
end
