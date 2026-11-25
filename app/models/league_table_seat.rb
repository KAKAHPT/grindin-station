# frozen_string_literal: true

# A player's place at a league table. `active` holds the player to the table (waiting, or filled and not
# settled yet); the database allows one active seat per player.
class LeagueTableSeat < ApplicationRecord
  belongs_to :league_table, inverse_of: :seats
  belongs_to :event_participant

  scope :active, -> { where(active: true) }
end
