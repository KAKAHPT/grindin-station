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
      swaps += 1 while swaps < MAX_SWAPS_PER_POD * @pods.size && apply_first_improving_swap!

      @pods.sum { |pod| pod.candidates.combination(2).count { |a, b| met?(a, b) } }
    end

    private

    def apply_first_improving_swap!
      @pods.each do |pod|
        pod.candidates.each do |player|
          next if rematches(player, pod.candidates).zero?

          @pods.each do |other_pod|
            next if other_pod.equal?(pod)

            other_pod.candidates.each do |other|
              next unless swap_improves?(player, pod, other, other_pod)

              swap!(player, pod, other, other_pod)
              return true
            end
          end
        end
      end
      false
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

    def rematches(player, players)
      players.count { |p| met?(player, p) }
    end

    def met?(a, b)
      @opponent_ids[a.id].include?(b.id)
    end
  end
end
