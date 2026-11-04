# frozen_string_literal: true

module Tournaments
  # Job to create pods for a round
  class CreateSingleEliminationPodsJob < ApplicationJob
    def perform(round) # rubocop:disable Metrics/MethodLength -- the 1v1 dispatch line
      raise ArgumentError, "tournament has no top cut" unless round.event.rounds_info[:top]

      @round = round
      return pair_one_v_one_bracket! if round.event.one_v_one?

      @players_to_advance, @players_by_rank, @players_to_eliminate = initialize_players

      generate_pods!

      Tournaments::Strategies::SpreadMatcher.new(@round, @players_by_rank).match_players!

      @round.transaction do
        advance_players!
        eliminate_players!
        @round.pods.each(&:sit_participants!)
      end
    end

    private

    # 1v1 bracket (spec §5): the first cut round pairs seed i vs N+1-i (1v8, 2v7, 3v6, 4v5) and eliminates the
    # rest; each later round pairs the winners of pods i and k+1-i of the previous round. Seats by seed.
    def pair_one_v_one_bracket!
      field = bracket_field
      field.first(field.size / 2).each.with_index(1) do |player, number|
        @round.pods.build(number: number, size: 2).candidates = [player, field[-number]]
      end

      @round.transaction do
        eliminate_players!
        @round.pods.each(&:sit_participants!)
      end
    end

    def bracket_field
      ranked = Tournaments::PlayerSorter.new(@round).sorted_players
      return previous_round_winners(ranked.index_by(&:id)) if @round.number > @round.event.number_of_swiss_rounds + 1

      @players_to_eliminate = ranked.drop(players_making_the_cut)
      ranked.first(players_making_the_cut)
    end

    # The Advance in each pod of the previous cut round, in pod order.
    def previous_round_winners(players_by_id)
      previous = @round.event.rounds.find_by!(number: @round.number - 1)
      advanced = previous.results.where(type: "Advance").pluck(:event_participant_id).to_set
      previous.pods.includes(:seatings).order(:number).map { |pod| players_by_id.fetch(pod_winner(pod, advanced)) }
    end

    def pod_winner(pod, advanced)
      pod.seatings.map(&:event_participant_id).find { |id| advanced.include?(id) } ||
        raise(ArgumentError, "pod #{pod.number} has no winner")
    end

    def initialize_players
      sorted_players = Tournaments::PlayerSorter.new(@round).sorted_players
      players_continuing = sorted_players[0...players_making_the_cut]
      players_to_eliminate = sorted_players[players_making_the_cut..]
      players_being_paired = players_continuing.last(players_playing)
      players_to_advance = players_continuing - players_being_paired

      [players_to_advance, players_being_paired, players_to_eliminate]
    end

    def eliminate_players!
      @players_to_eliminate&.each do |player|
        Eliminated.create(round: @round, event_participant: player)
      end
    end

    def advance_players!
      @players_to_advance&.each do |player|
        Advance.create(round: @round, event_participant: player)
      end
    end

    def generate_pods!
      number_of_pods.times do |i|
        @round.pods.build(number: i + 1, size: @round.event.class::PREFERRED_POD_SIZE)
      end
    end

    def players_making_the_cut
      @round.event.rounds_info[:top][:players]
    end

    def players_playing
      number_of_pods * @round.event.class::PREFERRED_POD_SIZE
    end

    def number_of_pods
      @round.event.rounds_info[:top][:pods][@round.number - @round.event.number_of_swiss_rounds - 1]
    end
  end
end
