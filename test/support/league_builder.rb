# frozen_string_literal: true

# Builds leagues with real players for tests, without fixtures.
module LeagueBuilder
  extend self

  # A persisted League in `state` (no transition jobs run) with `players` enrolled participants.
  def build(players:, organizer:, state: :play, **settings) # rubocop:disable Metrics/AbcSize -- one record with its players
    suffix = SecureRandom.hex(4)
    league = League.create!({ name: "Liga #{suffix}", event_organizer: organizer, state: :draft, wager_percentage: 10,
                              start_time: 1.day.ago, end_time: 1.month.from_now }.merge(settings))
    players.times do |i|
      league.event_participants.create!(player_name: "Jogador #{i + 1}", accepted_terms: true,
                                        player_email: "liga-#{i + 1}-#{suffix}@example.com")
    end
    league.update_column(:state, League.states.fetch(state.to_s)) # rubocop:disable Rails/SkipsModelValidations
    league.reload
  end

  # Four players sit at a new table; returns its pod.
  def fill_table!(league, participants)
    table = Leagues::Tables::Open.call(league: league, participant: participants.first)
    participants.drop(1).each { |participant| Leagues::Tables::Join.call(table: table, participant: participant) }
    table.reload.pod
  end
end
