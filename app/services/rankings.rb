# frozen_string_literal: true

# M13 rankings: ranking points per (player, event) and Elo ratings, rebuilt by Rankings::Rebuild.
module Rankings
  # When the stored rankings were last rebuilt (nil before the first rebuild).
  def self.last_rebuilt_at = EloRating.maximum(:updated_at)
end
