# frozen_string_literal: true

module Tournaments
  # Simulates one swiss tournament without the database to measure seat fairness. Mimics the real pod
  # composition: players sorted by points (tiebreakers modelled as a random order), each equal-points group dealt by
  # seat need (PlayerSorter.deal), pods of 4 filled in that order with the remainder as pods of 3 at the bottom,
  # seats by Tournaments::SeatAssigner (seating: :random shuffles each pod instead, the baseline). Results: DRAW_RATE
  # of the pods draw (1 point each), otherwise one random winner (7 points). Rematch repair is skipped.
  class SeatSimulator
    DRAW_RATE = 0.3
    WIN_POINTS = 7
    DRAW_POINTS = 1
    POSITIONS = (1..5)
    SPREAD_POSITIONS = (1..4)

    # never_first_rate: fraction of players who never sat at seat 1. max_spread_le1_rate: fraction of players whose
    # max - min count over seats 1..4 is at most 1. worst: the 3 players with the largest spread => their counts.
    Report = Data.define(:never_first_rate, :max_spread_le1_rate, :worst, :seat_counts)

    def initialize(players:, rounds:, rng:, seating: :fair)
      @players = (1..players).to_a
      @seating = seating
      @rounds = rounds
      @rng = rng
      @points = @players.index_with(0)
      @seat_counts = @players.index_with { POSITIONS.index_with(0) }
    end

    def run
      @rounds.times { play_round }
      report
    end

    def self.spread(counts) = counts.values_at(*SPREAD_POSITIONS).minmax.then { |min, max| max - min }

    private

    def play_round
      pods(sorted_players).each do |pod|
        seat(pod.sort).each.with_index(1) { |player, position| @seat_counts[player][position] += 1 }
        score(pod)
      end
    end

    def seat(pod)
      return pod.shuffle(random: @rng) if @seating == :random

      SeatAssigner.new(participants: pod, seat_counts: @seat_counts, rng: @rng).order
    end

    def sorted_players
      ranked = @players.shuffle(random: @rng).sort_by.with_index { |player, i| [-@points[player], i] }
      ranked.chunk_while { |a, b| @points[a] == @points[b] }.flat_map { |group| PlayerSorter.deal(group, @seat_counts) }
    end

    # Pods of 4 from the top; when the count does not divide by 4, the last (4 - remainder) pods have 3.
    def pods(players)
      small = (4 - (players.size % 4)) % 4
      large = players.first(players.size - (3 * small))
      large.each_slice(4).to_a + players.last(3 * small).each_slice(3).to_a
    end

    def score(pod)
      if @rng.rand < DRAW_RATE
        pod.each { |player| @points[player] += DRAW_POINTS }
      else
        @points[pod[@rng.rand(pod.size)]] += WIN_POINTS
      end
    end

    def report
      spreads = @players.index_with { |player| self.class.spread(@seat_counts[player]) }
      worst = spreads.max_by(3) { |_, spread| spread }.to_h { |player, _| [player, @seat_counts[player]] }
      Report.new(
        never_first_rate: rate { |player| @seat_counts[player][1].zero? },
        max_spread_le1_rate: rate { |player| spreads[player] <= 1 },
        worst: worst,
        seat_counts: @seat_counts
      )
    end

    def rate(&) = @players.count(&).fdiv(@players.size)
  end
end
