# frozen_string_literal: true

module Profiles
  # Profile totals from Profiles::History rows: events, top cuts, wins (1st place), top 4, win rate
  # (wins over games), conversion rate (cuts over events) in whole percents (nil without a denominator),
  # and the four most played commanders as [[name, count], ...].
  class Summary
    Result = Data.define(:events, :top_cuts, :win_rate, :conversion_rate, :wins, :top4, :commanders)

    def self.call(rows) = new(rows).call

    def initialize(rows)
      @rows = rows
    end

    def call
      top_cuts = @rows.count(&:made_cut)
      Result.new(events: @rows.size, top_cuts: top_cuts,
                 win_rate: percent(@rows.sum(&:wins), @rows.sum(&:games)),
                 conversion_rate: percent(top_cuts, @rows.size),
                 wins: @rows.count { |row| row.position == 1 },
                 top4: @rows.count { |row| row.position && row.position <= 4 },
                 commanders: commanders)
    end

    private

    def percent(part, whole)
      (part * 100.0 / whole).round unless whole.zero?
    end

    def commanders
      @rows.filter_map(&:commander).tally.sort_by { |name, count| [-count, name] }.first(4)
    end
  end
end
