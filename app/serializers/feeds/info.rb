# frozen_string_literal: true

module Feeds
  # {tid, name, updated (epoch seconds), state, starts_at, ends_at, players, round, timerEnd, format, matchGames,
  # pairingMode, unevenField, gameFormat}: round is the latest published one; format is "multiplayer" or "one_v_one",
  # matchGames 1 or 3 (best of), pairingMode "swiss", "power" or "random", unevenField "pods_of_three" or "byes" (both
  # nil for 1v1), gameFormat the 1v1 game format ("legacy", "modern", ...; nil for multiplayer).
  class Info
    def self.call(event, updated: Feeds.last_change(event)) = new(event).to_h(updated)

    def initialize(event)
      @event = event
    end

    def to_h(updated)
      round = @event.rounds.published.order(:number).includes(:results, pods: :seatings).last
      { tid: @event.slug, name: @event.name, updated: Feeds.epoch(updated), state: @event.state,
        starts_at: Feeds.iso(@event.start_time), ends_at: Feeds.iso(@event.end_time) }
        .merge(round_keys(round), format_keys)
    end

    private

    def format_keys
      { format: @event.format, matchGames: @event.match_games,
        pairingMode: (@event.pairing_mode unless @event.one_v_one?),
        unevenField: (@event.uneven_field unless @event.one_v_one?),
        gameFormat: (@event.game_format if @event.one_v_one?) }
    end

    def round_keys(round)
      { players: @event.playing_participants_count, round: round && Feeds.round_label(round),
        timerEnd: Feeds.timer_end(round) }
    end
  end
end
