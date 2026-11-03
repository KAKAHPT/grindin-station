# frozen_string_literal: true

module Tournaments
  # Post-pairing pass over a round's in-memory pod candidates: swaps players between pods while the
  # total number of rematch pairs strictly decreases. Swapped players must be within max_point_gap
  # match points of each other. Returns the number of rematch pairs left (an Integer).
  # Nearest first: a player with a rematch looks at the closest pods (|i - j| ascending) and, inside a pod,
  # at the candidates closest to them in match points. Callers widen max_point_gap step by step
  # (CreatePodsJob#repair_rematches!) so a swap only crosses points groups when nothing closer fixes it.
  class RematchRepair
    MAX_SWAPS_PER_POD = 20

    def initialize(round, max_point_gap:)
      @round = round
      @max_point_gap = max_point_gap
    end

    def repair!
      @pods = @round.pods.to_a
      @opponent_ids = @pods.flat_map(&:candidates).to_h { |player| [player.id, player.opponents.ids.to_set] }

      swaps = 0
      while swaps < MAX_SWAPS_PER_POD * @pods.size && (swap = first_improving_swap)
        swap!(*swap)
        swaps += 1
      end

      rematch_pairs
    end

    private

    # [player, pod, other, other_pod] for the first swap that lowers the rematch count, or nil.
    # Lowest-ranked first inside a pod, so a weaker player moves before a stronger one when either would do.
    def first_improving_swap
      @pods.each_with_index do |pod, index|
        pod.candidates.reverse_each do |player|
          next if rematches(player, pod.candidates).zero?

          swap = improving_swap_for(player, pod, index)
          return swap if swap
        end
      end
      nil
    end

    def improving_swap_for(player, pod, index)
      pods_by_distance(index).each do |other_pod|
        other =
          other_pod.candidates
            .sort_by.with_index { |candidate, k| [(candidate.match_points - player.match_points).abs, k] }
            .find { |candidate| swap_improves?(player, pod, candidate, other_pod) }
        return [player, pod, other, other_pod] if other
      end
      nil
    end

    # Every other pod, nearest table first (ties: the higher table).
    def pods_by_distance(index)
      (0...@pods.size).excluding(index).sort_by { |j| [(j - index).abs, j] }.map { |j| @pods[j] }
    end

    def swap_improves?(player, pod, other, other_pod)
      return false if (player.match_points - other.match_points).abs > @max_point_gap

      before = rematches(player, pod.candidates) + rematches(other, other_pod.candidates)
      after = rematches(other, pod.candidates - [player]) + rematches(player, other_pod.candidates - [other])
      after < before
    end

    def swap!(player, pod, other, other_pod)
      pod.candidates[pod.candidates.index(player)] = other
      other_pod.candidates[other_pod.candidates.index(other)] = player
    end

    def rematch_pairs
      @pods.sum { |pod| pod.candidates.combination(2).count { |player, other| met?(player, other) } }
    end

    def rematches(player, players)
      players.count { |other| met?(player, other) }
    end

    def met?(player, other)
      @opponent_ids[player.id].include?(other.id)
    end
  end
end
