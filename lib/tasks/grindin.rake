# frozen_string_literal: true

namespace :grindin do # rubocop:disable Metrics/BlockLength -- one task, kept in one place
  desc "Simulate n tournaments per pairing mode (default 2000, SIM_SEED=42); fail if seat fairness regresses"
  task :simulate, [:n] => :environment do |_, args| # rubocop:disable Metrics/BlockLength -- report + gate
    # Regression gate: need-aware dealing's measured levels (SIM_SEED=42, 2000 tournaments: 0.0112 / 0.8975)
    # with a margin of +0.005 / -0.02. The aspirational targets (nobody without seat 1, spread <= 1 for 99 %)
    # are in the notes. The gate applies to the fair seating of every pairing mode.
    never_first_max = 0.017
    spread_le1_min = 0.877
    notes = "docs/superpowers/notes/2026-10-27-seat-simulation.md"
    seatings = %i[fair random].freeze
    n = (args[:n] || 2000).to_i
    mean = ->(values) { values.sum.fdiv(values.size) }
    failed = false

    Tournaments::SeatSimulator::MODES.each do |mode| # rubocop:disable Metrics/BlockLength -- per-mode report + gate
      rng = Random.new((ENV["SIM_SEED"] || 42).to_i)
      runs =
        Array.new(n) do
          players = rng.rand(16..140)
          rounds = rng.rand(4..7)
          seed = rng.rand(2**32)
          reports =
            seatings.index_with do |seating|
              Tournaments::SeatSimulator.new(players: players, rounds: rounds, rng: Random.new(seed),
                                             seating: seating, mode: mode).run
            end
          [rounds, reports]
        end

      row =
        lambda do |label, group, seating|
          list = group.map { |_, reports| reports[seating] }
          worst = list.map { |report| report.worst.values.map { |counts| Tournaments::SeatSimulator.spread(counts) }.max }
          format("%<label>-8s %<seating>-7s %<n>6d %<never_first>12.4f %<spread>12.4f %<worst>10.2f %<max>6d",
                 label: label, seating: seating, n: list.size, never_first: mean.call(list.map(&:never_first_rate)),
                 spread: mean.call(list.map(&:max_spread_le1_rate)), worst: mean.call(worst), max: worst.max)
        end

      puts "== mode: #{mode}"
      puts "rounds   seating      n  never_first    spread<=1  worst avg    max"
      (runs.group_by(&:first).sort + [["all", runs]]).each do |rounds, group|
        seatings.each { |seating| puts row.call(rounds.to_s, group, seating) }
      end

      fair = runs.map { |_, reports| reports[:fair] }
      never_first = mean.call(fair.map(&:never_first_rate))
      spread = mean.call(fair.map(&:max_spread_le1_rate))
      puts "Regression gate [#{mode}] (never_first <= #{never_first_max}, spread<=1 >= #{spread_le1_min}); " \
           "aspirational targets in #{notes}"
      if never_first > never_first_max || spread < spread_le1_min
        failed = true
        puts "FAIL [#{mode}] (never_first_rate #{never_first.round(4)}, max_spread_le1_rate #{spread.round(4)})"
      else
        puts "OK [#{mode}] (never_first_rate #{never_first.round(4)}, max_spread_le1_rate #{spread.round(4)})"
      end
    end

    exit 1 if failed
  end
end
