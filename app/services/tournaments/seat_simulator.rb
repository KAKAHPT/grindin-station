# frozen_string_literal: true

module Tournaments
  # Simulates one swiss tournament without the database to measure seat fairness. Mimics the real pod
  # composition: players sorted by points (tiebreakers modelled as a random order), each equal-points group dealt by
  # seat need (PlayerSorter.deal), pods of 4 filled in that order with the remainder as pods of 3 at the bottom,
  # seats by Tournaments::SeatAssigner (seating: :random shuffles each pod instead, the baseline). Results: DRAW_RATE
  # of the pods draw (1 point each), otherwise one random winner (7 points). Rematch repair is skipped.
  # short_repair: true (default) runs Tournaments::ShortPodRepair over the pods (short count = rounds in a pod of 3,
  # no byes here; met always false) on the CreatePodsJob ladder: same points, a draw, one win; false is the baseline.
  # mode: :swiss as above; :random shuffles the whole field each round and deals it as one group; :power is identical
  # to :swiss here, because the simulator never modelled the spread (power-matching) round.
  class SeatSimulator
    DRAW_RATE = 0.3
    WIN_POINTS = 7
    DRAW_POINTS = 1
    MODES = %i[swiss power random].freeze
    POSITIONS = (1..5)
    SPREAD_POSITIONS = (1..4)

    # never_first_rate: fraction of players who never sat at seat 1. max_spread_le1_rate: fraction of players whose
    # max - min count over seats 1..4 is at most 1. worst: the 3 players with the largest spread => their counts.
    # short_spread / short_max: max - min / max of the players' short counts (rounds in a pod of 3).
    Report = Data.define(:never_first_rate, :max_spread_le1_rate, :worst, :seat_counts, :short_spread, :short_max)
    SHORT_POD_GAPS = [0, DRAW_POINTS, WIN_POINTS].freeze

    def initialize(players:, rounds:, rng:, seating: :fair, mode: :swiss, short_repair: true) # rubocop:disable Metrics/ParameterLists
      raise ArgumentError, "unknown mode #{mode.inspect}" unless MODES.include?(mode)

      @mode = mode
      @players = (1..players).to_a
      @seating = seating
      @rounds = rounds
      @rng = rng
      @points = @players.index_with(0)
      @seat_counts = @players.index_with { POSITIONS.index_with(0) }
      @short_repair = short_repair
      @short_counts = @players.index_with(0)
    end

    def run
      @rounds.times { play_round }
      report
    end

    def self.spread(counts) = counts.values_at(*SPREAD_POSITIONS).minmax.then { |min, max| max - min }

    private

    def play_round
      round_pods = pods(sorted_players)
      repair_short_pods!(round_pods) if @short_repair
      round_pods.each do |pod|
        pod.each { |player| @short_counts[player] += 1 } if pod.size == 3
        seat(pod.sort).each.with_index(1) { |player, position| @seat_counts[player][position] += 1 }
        score(pod)
      end
    end

    def seat(pod)
      return pod.shuffle(random: @rng) if @seating == :random

      SeatAssigner.new(participants: pod, seat_counts: @seat_counts, rng: @rng).order
    end

    def sorted_players
      return PlayerSorter.deal(@players.shuffle(random: @rng), @seat_counts) if @mode == :random

      ranked = @players.shuffle(random: @rng).sort_by.with_index { |player, i| [-@points[player], i] }
      ranked.chunk_while { |a, b| @points[a] == @points[b] }.flat_map { |group| PlayerSorter.deal(group, @seat_counts) }
    end

    # Pods of 4 from the top; when the count does not divide by 4, the last (4 - remainder) pods have 3.
    def pods(players)
      small = (4 - (players.size % 4)) % 4
      large = players.first(players.size - (3 * small))
      large.each_slice(4).to_a + players.last(3 * small).each_slice(3).to_a
    end

    def repair_short_pods!(round_pods)
      small, large = round_pods.partition { |pod| pod.size == 3 }
      return if small.empty?

      SHORT_POD_GAPS.each do |gap|
        repair = ShortPodRepair.new(small: small, large: large, short_count: @short_counts.method(:fetch),
                                    points: @points.method(:fetch), met: ->(_, _) { false }, max_point_gap: gap)
        break if repair.repair!.zero?
      end
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
        seat_counts: @seat_counts,
        **short_stats
      )
    end

    def short_stats
      min, max = @short_counts.values.minmax
      { short_spread: max - min, short_max: max }
    end

    def rate(&block) = @players.count(&block).fdiv(@players.size)
  end
end
