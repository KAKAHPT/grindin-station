# frozen_string_literal: true

module Tournaments
  # Post-pairing pass over a round's in-memory pod candidates: swaps players between pods while the
  # total number of rematch pairs strictly decreases. Swapped players must be within max_point_gap
  # match points of each other. Returns the number of rematch pairs left.
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
    def first_improving_swap
      @pods.each do |pod|
        pod.candidates.each do |player|
          next if rematches(player, pod.candidates).zero?

          swap = improving_swap_for(player, pod)
          return swap if swap
        end
      end
      nil
    end

    def improving_swap_for(player, pod)
      @pods.each do |other_pod|
        next if other_pod.equal?(pod)

        other = other_pod.candidates.find { |candidate| swap_improves?(player, pod, candidate, other_pod) }
        return [player, pod, other, other_pod] if other
      end
      nil
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
