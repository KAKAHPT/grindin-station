# frozen_string_literal: true

module Tournaments
  class FinishTournamentJob < ApplicationJob
    def perform(tournament)
      record_final_positions(tournament)
      post_result(tournament)
      if tournament.circuit.present?
        Circuits::UpdateStandingsJob.perform_now(tournament.circuit, tournament)
      end
      Rankings::RebuildJob.schedule!
    end

    private

    # The feed's result post, once per finish: "<winner> won <event> (<n> players)", signed by the organizer.
    def post_result(tournament)
      winner = tournament.event_participants.find_by(final_position: 1)
      author = tournament.event_organizer&.user
      return unless winner && author
      return if Post.exists?(event: tournament, kind: "result")

      players = tournament.event_participants.where(waitlisted: false).count
      Post.create!(user: author, event: tournament, kind: "result",
                   body: I18n.t("feed.result_body", winner: winner.name, event: tournament.name, count: players))
    end

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
