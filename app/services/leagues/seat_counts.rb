# frozen_string_literal: true

module Leagues
  # How often each player sat in each seat in the league's games: { participant id => { seat => times } }.
  module SeatCounts
    def self.for(league, participant_ids)
      counts = Seating.joins(pod: :round)
        .where(rounds: { event_id: league.id, type: "LeagueGameRound" }, event_participant_id: participant_ids)
        .group(:event_participant_id, :order).count
      participant_ids.index_with do |id|
        EventParticipant.empty_seat_counts.merge(counts.select { |(pid, _), _| pid == id }.transform_keys(&:last))
      end
    end
  end
end
