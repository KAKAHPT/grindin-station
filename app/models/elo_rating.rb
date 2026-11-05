# frozen_string_literal: true

# A player's Elo rating for a season (calendar year) or all time (season nil), rebuilt by Rankings::Rebuild.
class EloRating < ApplicationRecord
  belongs_to :player
end
