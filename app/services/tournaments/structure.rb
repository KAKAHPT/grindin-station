# frozen_string_literal: true

module Tournaments
  # Suggested swiss rounds and top cut for a number of players (the organiser can change both before the swiss).
  module Structure
    module_function

    def suggested(player_count)
      swiss_rounds, top_cut_size =
        case player_count
        when ...4 then [0, 0]
        when 4..5 then [3, 0]
        when 6..7 then [3, 4]
        when 8..23 then [4, 4]
        when 24..31 then [4, 10]
        when 32..39 then [4, 13]
        when 40..63 then [5, 16]
        when 64..127 then [6, 16]
        else [7, 40]
        end
      { swiss_rounds: swiss_rounds, top_cut_size: top_cut_size }
    end
  end
end
