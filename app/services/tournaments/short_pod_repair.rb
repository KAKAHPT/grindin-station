# frozen_string_literal: true

module Tournaments
  # Post-pairing pass after RematchRepair: swaps players out of the pods of 3 (small) into the pods of 4 (large)
  # while a player sitting short again can trade places with a player who has sat short fewer times
  # (short count = swiss rounds in a pod of 3 plus byes). A swap stays within max_point_gap match points and never
  # adds a rematch over the two pods involved. Pure: candidate Arrays, mutated in place, and lambdas, so the job
  # and the simulator share it. Returns the players left in a small pod with a short count above zero.
  # Pod order is the combined list, large pods first then small; a small pod looks at the nearest large pod first.
  class ShortPodRepair
    MAX_SWAPS_PER_POD = 20

    def initialize(small:, large:, short_count:, points:, met:, max_point_gap:) # rubocop:disable Metrics/ParameterLists
      @small = small
      @large = large
      @short_count = short_count
      @points = points
      @met = met
      @max_point_gap = max_point_gap
    end

    def repair!
      swaps = 0
      while swaps < MAX_SWAPS_PER_POD * (@small.size + @large.size) && (swap = first_improving_swap)
        swap!(*swap)
        swaps += 1
      end

      @small.sum { |pod| pod.count { |player| @short_count.call(player).positive? } }
    end

    private

    # [player, pod, other, other_pod] for the first improving swap, or nil. Last small pod first and
    # lowest-ranked first inside it, so the weaker repeating player moves when only one swap is available.
    def first_improving_swap
      (@small.size - 1).downto(0) do |index|
        pod = @small[index]
        pod.reverse_each do |player|
          next unless @short_count.call(player).positive?

          swap = swap_for(player, pod, @large.size + index)
          return swap if swap
        end
      end
      nil
    end

    def swap_for(player, pod, position)
      large_by_distance(position).each do |other_pod|
        other =
          other_pod
            .sort_by.with_index { |candidate, k| [(@points.call(candidate) - @points.call(player)).abs, k] }
            .find { |candidate| swap_allowed?(player, pod, candidate, other_pod) }
        return [player, pod, other, other_pod] if other
      end
      nil
    end

    # Large pods nearest to `position` in the combined list (ties: the higher table).
    def large_by_distance(position)
      (0...@large.size).sort_by { |j| [(position - j).abs, j] }.map { |j| @large[j] }
    end

    def swap_allowed?(player, pod, other, other_pod)
      return false unless @short_count.call(other) < @short_count.call(player)
      return false if (@points.call(player) - @points.call(other)).abs > @max_point_gap

      before = rematch_pairs(pod) + rematch_pairs(other_pod)
      after = rematch_pairs(pod - [player] + [other]) + rematch_pairs(other_pod - [other] + [player])
      after <= before
    end

    def swap!(player, pod, other, other_pod)
      pod[pod.index(player)] = other
      other_pod[other_pod.index(other)] = player
    end

    def rematch_pairs(players)
      players.combination(2).count { |a, b| @met.call(a, b) }
    end
  end
end
