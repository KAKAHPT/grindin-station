# frozen_string_literal: true

module Tournaments
  class FinishTournamentJob < ApplicationJob
    def perform(tournament)
      record_final_positions(tournament)
      if tournament.circuit.present?
        Circuits::UpdateStandingsJob.perform_now(tournament.circuit, tournament)
      end
    end

    private

    # Every non-waitlisted participant gets a unique position 1..N: playing players before dropped ones, each
    # group by rank_score, which puts top-cut advancements first (the cut winner, then the finalists, then
    # earlier eliminations) and then the swiss order. Waitlisted players get nil; finishing again recomputes.
    def record_final_positions(tournament)
      positions = Arel::Nodes::Case.new(EventParticipant.arel_table[:id])
      ranked = final_order(tournament)
      ranked.each.with_index(1) { |participant, position| positions.when(participant.id).then(position) }

      tournament.transaction do
        tournament.event_participants.update_all(final_position: ranked.empty? ? nil : positions) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def final_order(tournament)
      EventParticipant.standings_for(tournament).reject(&:waitlisted?)
        .sort_by { |participant| [participant.playing? ? 0 : 1, -participant.rank_score, participant.id] }
    end
  end
end
