# frozen_string_literal: true

# One player's ranking points from one finished event (M13), rebuilt by Rankings::Rebuild; read-only for pages.
# country/team are snapshots of the player's account at rebuild.
class RankingContribution < ApplicationRecord
  belongs_to :player
  belongs_to :event
  belongs_to :event_organizer, optional: true
end
