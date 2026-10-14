# frozen_string_literal: true

module Tournaments
  module Strategies
    class SwissMatcher
      def initialize(round, sorted_players)
        @round = round
        @sorted_players = sorted_players
        @player_pods = {}
      end

      def match_players!
        initial_match!
      end

      private

      def initial_match!
        @round.pods.each do |pod|
          @sorted_players.each do |player|
            next if @player_pods[player].present?

            @player_pods[player] = pod if pod.force_candidate(player)

            break if pod.full?
          end
        end
      end
    end
  end
end
