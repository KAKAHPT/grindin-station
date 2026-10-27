# frozen_string_literal: true

module Tournaments
  # Job to create pods for a round
  class CreatePodsJob < ApplicationJob
    def perform(round)
      @round = round
      Tournaments::UnevenPodGenerator.new(@round).generate_pods!
      @players_by_rank = Tournaments::PlayerSorter.new(@round).paired_players

      match_according_to_strategy!
      repair_rematches!

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

    # Every strategy repairs with an escalating points gap: same points first, then a draw, a win, two wins, ...,
    # and any gap only as a last resort, stopping as soon as no rematch is left. Nobody leaves their points group
    # while a swap inside it fixes the rematch, so the leaders stay at the top tables.
    # NOTE: grindin:simulate (Tournaments::SeatSimulator) skips this repair, so its seat numbers assume the repair
    # does not move players far from the tables the pairing gave them.
    def repair_rematches!
      rematch_gaps.each do |gap|
        break if Tournaments::RematchRepair.new(@round, max_point_gap: gap).repair!.zero?
      end
    end

    def rematch_gaps
      event = @round.event
      wins = (1...@round.number).map { |count| count * event.points_win }
      ([0, event.points_draw] + wins).uniq.sort + [Float::INFINITY]
    end

    # Rounds beyond the thresholds table play as :standard.
    def load_strategy
      @round.event.rounds_info[:rounds][@round.number - 1]&.values&.first || :standard
    end
  end
end
