# frozen_string_literal: true

namespace :grindin do
  desc "Simulate n swiss tournaments (default 2000, SIM_SEED=42); fail if seat fairness regresses"
  task :simulate, [:n] => :environment do |_, args|
    # Regression gate: need-aware dealing's measured levels (SIM_SEED=42, 2000 tournaments: 0.0112 / 0.8975)
    # with a margin of +0.005 / -0.02. The aspirational targets (nobody without seat 1, spread <= 1 for 99 %)
    # are in the notes.
    never_first_max = 0.017
    spread_le1_min = 0.877
    notes = "docs/superpowers/notes/2026-10-27-seat-simulation.md"
    n = (args[:n] || 2000).to_i
    rng = Random.new((ENV["SIM_SEED"] || 42).to_i)
    runs = Array.new(n) do
      players = rng.rand(16..140)
      rounds = rng.rand(4..7)
      seed = rng.rand(2**32)
      reports = %i[fair random].to_h do |seating|
        [seating, Tournaments::SeatSimulator.new(players:, rounds:, rng: Random.new(seed), seating:).run]
      end
      [rounds, reports]
    end

    mean = ->(values) { values.sum.fdiv(values.size) }
    row = lambda do |label, group, seating|
      list = group.map { |_, reports| reports[seating] }
      worst = list.map { |report| report.worst.values.map { |counts| Tournaments::SeatSimulator.spread(counts) }.max }
      format("%-8s %-7s %6d %12.4f %12.4f %10.2f %6d", label, seating, list.size, mean.(list.map(&:never_first_rate)),
             mean.(list.map(&:max_spread_le1_rate)), mean.(worst), worst.max)
    end

    puts format("%-8s %-7s %6s %12s %12s %10s %6s", "rounds", "seating", "n", "never_first", "spread<=1",
                "worst avg", "max")
    (runs.group_by(&:first).sort + [["all", runs]]).each do |rounds, group|
      %i[fair random].each { |seating| puts row.(rounds.to_s, group, seating) }
    end

    fair = runs.map { |_, reports| reports[:fair] }
    never_first = mean.(fair.map(&:never_first_rate))
    spread = mean.(fair.map(&:max_spread_le1_rate))
    puts "Regression gate (never_first <= #{never_first_max}, spread<=1 >= #{spread_le1_min}); " \
         "aspirational targets in #{notes}"
    if never_first > never_first_max || spread < spread_le1_min
      puts "FAIL (never_first_rate #{never_first.round(4)}, max_spread_le1_rate #{spread.round(4)})"
      exit 1
    end
    puts "OK (never_first_rate #{never_first.round(4)}, max_spread_le1_rate #{spread.round(4)})"
  end
end
