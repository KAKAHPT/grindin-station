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

    # Short pods (M11): 13 players = 1x4 + 3x3 every round. Gate: the repaired mean spread of short counts never
    # above the baseline, nor above its measured level (SIM_SEED=42, 2000 runs) + 0.1;
    # see docs/superpowers/notes/2026-11-05-m11-uneven-field.md.
    short_spread_level = 1.463
    rng = Random.new((ENV["SIM_SEED"] || 42).to_i)
    seeds = Array.new(n) { rng.rand(2**32) }
    short =
      [true, false].index_with do |short_repair|
        reports =
          seeds.map do |seed|
            Tournaments::SeatSimulator.new(players: 13, rounds: 4, rng: Random.new(seed),
                                           short_repair: short_repair).run
          end
        { spread: mean.call(reports.map(&:short_spread)), max: mean.call(reports.map(&:short_max)) }
      end
    puts "== short pods (13 players, 4 rounds)"
    puts "repair       n  spread avg  max avg"
    short.each do |repair, means|
      puts format("%<repair>-6s %<n>6d %<spread>11.4f %<max>8.4f", repair: repair, n: n, **means)
    end
    spread = short[true][:spread]
    puts "Regression gate [short pods] (spread <= baseline #{short[false][:spread].round(4)} and <= " \
         "#{(short_spread_level + 0.1).round(4)})"
    if spread > short[false][:spread] || spread > short_spread_level + 0.1
      failed = true
      puts "FAIL [short pods] (short_spread #{spread.round(4)})"
    else
      puts "OK [short pods] (short_spread #{spread.round(4)})"
    end

    exit 1 if failed
  end
end
