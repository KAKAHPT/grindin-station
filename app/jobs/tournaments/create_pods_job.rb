# frozen_string_literal: true

module Tournaments
  # Job to create pods for a round
  class CreatePodsJob < ApplicationJob
    def perform(round)
      @round = round
      Tournaments::UnevenPodGenerator.new(@round).generate_pods!
      @players_by_rank = Tournaments::PlayerSorter.new(@round).sorted_players

      match_according_to_strategy!
      Tournaments::RematchRepair.new(@round, max_point_gap: gap_for(load_strategy)).repair!

      @round.transaction do
        @round.pods.each(&:sit_participants!)
      end
    end

    private

    def match_according_to_strategy!
      case load_strategy
      when :spread
        Tournaments::Strategies::SpreadMatcher.new(@round, @players_by_rank).match_players!
      when :forced, :standard
        Tournaments::Strategies::SwissMatcher.new(@round, @players_by_rank).match_players!
      end
    end

    def gap_for(strategy)
      strategy == :standard ? 0 : Float::INFINITY
    end

    # Rounds beyond the thresholds table play as :standard.
    def load_strategy
      @round.event.rounds_info[:rounds][@round.number - 1]&.values&.first || :standard
    end
  end
end
