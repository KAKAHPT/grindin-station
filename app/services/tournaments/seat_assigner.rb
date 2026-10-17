# frozen_string_literal: true

module Tournaments
  # Fair seat order for one swiss pod. Seat 1 must go to a player with the fewest seat-1s so far; among those
  # orders, the one with the lowest cost wins, where cost = sum over seats of WEIGHTS[seat] * (times the player
  # already sat there)². Ties are drawn with rng over the tied orders in a stable order, so a seed reproduces them.
  class SeatAssigner
    WEIGHTS = { 1 => 3, 2 => 1, 3 => 1, 4 => 2, 5 => 2 }.freeze

    # participants: Array (3-5); seat_counts: participant => { position => times }; rng: Random.
    def initialize(participants:, seat_counts:, rng:)
      @participants = participants
      @seat_counts = seat_counts
      @rng = rng
    end

    def order = choice.first

    def cost = choice.last

    private

    def choice
      @choice ||=
        begin
          scored = eligible_orders.map { |indices| [indices, cost_of(indices)] }
          best = scored.map(&:last).min
          tied = scored.select { |_, cost| cost == best }.map(&:first).sort
          [tied[@rng.rand(tied.size)].map { |i| @participants[i] }, best]
        end
    end

    # Permutations of participant indices whose first player has the fewest seat-1s in the pod.
    def eligible_orders
      fewest = @participants.map { |participant| @seat_counts[participant][1] }.min
      (0...@participants.size).to_a.permutation.select do |indices|
        @seat_counts[@participants[indices.first]][1] == fewest
      end
    end

    def cost_of(indices)
      indices.each.with_index(1).sum do |i, position|
        WEIGHTS[position] * (@seat_counts[@participants[i]][position]**2)
      end
    end
  end
end
