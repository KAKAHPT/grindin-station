# frozen_string_literal: true

module Leagues
  # Pods of a league's cut round. The first round takes the league's qualified field (League#cut_field) and
  # eliminates everyone else; the later rounds pair whoever advanced, like a tournament.
  class CreateCutPodsJob < Tournaments::CreateSingleEliminationPodsJob
    private

    def initialize_players # rubocop:disable Metrics/AbcSize
      return super unless first_stage?

      everyone = Tournaments::PlayerSorter.new(@round).sorted_players
      qualified = @round.event.cut_field.map(&:id)
      continuing =
        everyone.select { |player| qualified.first(players_making_the_cut).include?(player.id) }
          .sort_by { |player| qualified.index(player.id) }
      paired = continuing.last(players_playing)
      [continuing - paired, paired, everyone - continuing]
    end

    def first_stage? = @round.number == @round.event.number_of_swiss_rounds + 1
  end
end
