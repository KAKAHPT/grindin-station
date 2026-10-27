# frozen_string_literal: true

module Tournaments
  # Suggested swiss rounds and top cut for a number of players (the organiser can change both before the swiss).
  module Structure
    extend self

    # player count range => [swiss rounds, top cut size]
    SUGGESTIONS = {
      ...4 => [0, 0],
      4..5 => [3, 0],
      6..7 => [3, 4],
      8..23 => [4, 4],
      24..31 => [4, 10],
      32..39 => [4, 13],
      40..63 => [5, 16],
      64..127 => [6, 16],
      128.. => [7, 40]
    }.freeze

    def suggested(player_count)
      swiss_rounds, top_cut_size = SUGGESTIONS.find { |range, _| range.cover?(player_count) }.last
      { swiss_rounds: swiss_rounds, top_cut_size: top_cut_size }
    end
  end
end
