# frozen_string_literal: true

module Leagues
  # The league is over: final positions, circuit points, rankings.
  class FinishLeagueJob < ApplicationJob
    def perform(league)
      record_final_positions(league) if league.play_mode_open_tables?
      Circuits::UpdateStandingsJob.perform_now(league.circuit, league) if league.circuit.present?
      Rankings::RebuildJob.schedule!
    end

    private

    # 1..N for everyone in the standings: the cut first (its winner, then who went furthest), then the
    # league standings; players still in before those who dropped.
    def record_final_positions(league) # rubocop:disable Metrics/AbcSize
      cut = cut_progress(league)
      ranked =
        league.ranked_participants.each_with_index.sort_by do |participant, standing|
          advanced, reached = cut.fetch(participant.id, [0, 0])
          [participant.playing? ? 0 : 1, -advanced, -reached, standing]
        end
      positions = Arel::Nodes::Case.new(EventParticipant.arel_table[:id])
      ranked.each.with_index(1) { |(participant, _), position| positions.when(participant.id).then(position) }
      league.event_participants.update_all(final_position: ranked.empty? ? nil : positions) # rubocop:disable Rails/SkipsModelValidations
    end

    # { participant id => [cut rounds won, last cut round played] }
    def cut_progress(league) # rubocop:disable Metrics/AbcSize
      rounds = league.rounds.where(type: "LeagueCutRound")
      advanced = Result.current.where(round: rounds, type: "Advance").group(:event_participant_id).count
      reached = Seating.joins(pod: :round).where(rounds: { id: rounds.select(:id) })
        .group(:event_participant_id).maximum("rounds.number")
      (advanced.keys | reached.keys).index_with { |id| [advanced.fetch(id, 0), reached.fetch(id, 0)] }
    end
  end
end
