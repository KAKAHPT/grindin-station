# frozen_string_literal: true

module Rankings
  # Ranking points of one player in one event (spec M13 D4): 3 per win, 1 per draw or bye, 0 per loss;
  # tournaments add +5 for the cut, +5 for a top 4 in the cut, +10 for the win; the sum times the field factor.
  module Points
    extend self

    # [largest field, factor], by the number of non-waitlisted participants.
    FIELD_FACTORS = [[16, 1], [32, 1.25], [64, 1.5], [Float::INFINITY, 2]].freeze

    def factor(field) = FIELD_FACTORS.find { |largest, _| field <= largest }.last

    def games(wins:, draws:, byes:) = (3 * wins) + draws + byes

    # Independent terms: a winner without a cut still gets the +10.
    def bonuses(made_cut:, top4:, won:) = (made_cut ? 5 : 0) + (top4 ? 5 : 0) + (won ? 10 : 0)

    # Leagues get games only.
    def total(field:, wins:, draws:, byes:, made_cut:, top4:, won:, league: false) # rubocop:disable Metrics/ParameterLists
      base = games(wins: wins, draws: draws, byes: byes)
      base += bonuses(made_cut: made_cut, top4: top4, won: won) unless league
      (BigDecimal(base) * BigDecimal(factor(field).to_s)).round(2)
    end
  end
end
