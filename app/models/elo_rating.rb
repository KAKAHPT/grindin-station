# frozen_string_literal: true

# A player's Elo rating in one play pool (Event::PLAYS: the multiplayer pods or one 1v1 game format, M15 D6) for a
# season (calendar year) or all time (season nil), rebuilt by Rankings::Rebuild.
class EloRating < ApplicationRecord
  belongs_to :player
end
