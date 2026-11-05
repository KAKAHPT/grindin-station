# frozen_string_literal: true

module Exports
  # Final (or current) standings in the public order, dropped players after the active ones.
  module Standings
    COMMON = %w[standing name email points wins draws losses byes].freeze
    MULTIPLAYER = %w[winRate opponentWinRate].freeze
    ONE_V_ONE = %w[omw gw ogw].freeze

    def self.call(event)
      active, dropped = Feeds::Standings.ranked(event).partition(&:playing?)
      rows = (active + dropped).each.with_index(1).map { |participant, standing| row(event, participant, standing) }
      CsvFile.generate(COMMON + (event.one_v_one? ? ONE_V_ONE : MULTIPLAYER) + %w[dropped], rows)
    end

    def self.row(event, participant, standing)
      [standing, participant.name, participant.player.reporting_email, participant.match_points,
       participant.number_of_wins, participant.number_of_draws, participant.number_of_losses,
       participant.number_of_byes, *rates(event, participant), participant.dropped? ? "yes" : "no"]
    end

    def self.rates(event, participant)
      rates =
        if event.one_v_one?
          [participant.opponents_match_win_rate, participant.game_win_rate, participant.opponents_game_win_rate]
        else
          [participant.win_rate, participant.opponents_win_rate]
        end
      rates.map { |rate| CsvFile.rate(rate) }
    end
  end
end
