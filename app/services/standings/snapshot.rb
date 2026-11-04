# frozen_string_literal: true

module Standings
  # Writes every participant's rank when a round closes, in the order of the public standings
  # (Feeds::Standings.ranked). Re-closing the same round replaces its snapshot.
  class Snapshot
    def self.call(event, round)
      rows = rows(event, round)
      StandingsSnapshot.transaction do
        StandingsSnapshot.where(event_id: event.id, round_number: round.number).delete_all
        StandingsSnapshot.insert_all!(rows) if rows.any? # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def self.rows(event, round)
      Feeds::Standings.ranked(event).each.with_index(1).map do |participant, rank|
        { event_id: event.id, round_number: round.number, event_participant_id: participant.id, rank: rank }
      end
    end

    # Undoing a round reopens the one before it: neither has final standings any more.
    def self.discard(event, from_round_number)
      StandingsSnapshot.where(event_id: event.id, round_number: from_round_number..).delete_all
    end
  end
end
