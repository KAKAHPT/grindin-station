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

    # 1v1 per MTR Appendix E (straight single elimination below 9 players; 5-7 give the top seeds walkovers)
    ONE_V_ONE_SUGGESTIONS = {
      ...4 => [0, 0],
      4..4 => [0, 4],
      5..8 => [0, 8],
      9..16 => [5, 4],
      17..32 => [5, 8],
      33..64 => [6, 8],
      65..128 => [7, 8],
      129..226 => [8, 8],
      227..409 => [9, 8],
      410.. => [10, 8]
    }.freeze

    def suggested(player_count, format: "multiplayer")
      table = format == "one_v_one" ? ONE_V_ONE_SUGGESTIONS : SUGGESTIONS
      swiss_rounds, top_cut_size = table.find { |range, _| range.cover?(player_count) }.last
      { swiss_rounds: swiss_rounds, top_cut_size: top_cut_size }
    end
  end
end
