# frozen_string_literal: true

# A participant's rank in the standings when a round closed (Standings::Snapshot), keyed by round number.
class StandingsSnapshot < ApplicationRecord
  belongs_to :event
  belongs_to :event_participant

  # participant id => places moved between the two latest snapshots of the event (positive = up);
  # empty before two swiss rounds have closed and once the swiss is over (cut or finished). One query.
  def self.movements_for(event)
    return {} unless event.state == "swiss"

    before, after = latest_two_ranks(event.id)
    return {} unless after

    after.filter_map { |id, rank| [id, before[id] - rank] if before[id] }.to_h
  end

  # [{participant id => rank}, ...] for the event's two latest round numbers, older first.
  def self.latest_two_ranks(event_id)
    numbers = where(event_id: event_id).select(:round_number).distinct.order(round_number: :desc).limit(2)
    where(event_id: event_id, round_number: numbers).pluck(:round_number, :event_participant_id, :rank)
      .group_by(&:first).sort.map { |_, rows| rows.to_h { |_, id, rank| [id, rank] } }
  end
end
