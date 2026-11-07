# frozen_string_literal: true

module Grindin
  # One block of the public seat-fairness report (grindin:seat_report): `per` simulated swiss tournaments of 50-60
  # players with `rounds` rounds, each run twice on the same seed (Grindin's weighted seats, then random seats).
  # Per seating: the share of players whose seat spread (max - min count over seats 1-4) is at most 1 (fair_rate),
  # the share who never sat at seat 1 (never_first), the spread histogram 0/1/2/3+, the seat-1 count histogram,
  # each seat's share of all chairs and the worst player's counts over seats 1-4.
  class SeatReport
    SEATINGS = %i[fair random].freeze
    PLAYERS = (50..60)

    def initialize(rounds:, per:, rng:)
      @rounds = rounds
      @seeds = Array.new(per) { [rng.rand(PLAYERS), rng.rand(2**32)] }
    end

    def call
      SEATINGS.index_with { |seating| summarize(seating) }
    end

    private

    def summarize(seating)
      tally = Tally.new(@rounds)
      @seeds.each do |players, seed|
        simulator = Tournaments::SeatSimulator.new(players: players, rounds: @rounds, rng: Random.new(seed),
                                                   seating: seating)
        tally.add(simulator.run)
      end
      tally.to_h.merge(tournaments: @seeds.size)
    end

    # Accumulates the per-player seat counts of every simulated tournament.
    class Tally
      def initialize(rounds)
        @rounds = rounds
        @players = 0
        @spreads = Hash.new(0)
        @first_counts = Hash.new(0)
        @seat_totals = Hash.new(0)
        @worst = nil
      end

      def add(report)
        report.seat_counts.each_value { |counts| add_player(counts) }
        worst = report.worst.values.first
        @worst = worst if worst && (@worst.nil? || spread(worst) > spread(@worst))
      end

      def to_h
        { players: @players, fair_rate: pct(@spreads[0] + @spreads[1]), never_first: pct(@first_counts[0], 2),
          spread: (0..3).map { |k| pct(@spreads[k]) }, first_counts: first_counts, seat_share: seat_share,
          worst_example: @worst&.values_at(1, 2, 3, 4) }
      end

      private

      def first_counts = (0..[@rounds, 4].min).map { |k| pct(@first_counts[k]) }

      def seat_share = (1..4).map { |seat| (@seat_totals[seat] * 100.0 / @seat_totals.values.sum).round(1) }

      def add_player(counts)
        @players += 1
        @spreads[[spread(counts), 3].min] += 1
        @first_counts[counts[1]] += 1
        (1..4).each { |seat| @seat_totals[seat] += counts[seat] }
      end

      def spread(counts) = Tournaments::SeatSimulator.spread(counts)

      def pct(count, digits = 1) = (count * 100.0 / @players).round(digits)
    end
  end
end
