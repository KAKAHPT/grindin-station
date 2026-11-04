# frozen_string_literal: true

module Feeds
  # {tid, name, state, starts_at, ends_at, players, round, timerEnd}: round is the latest published one.
  class Info
    def self.call(event, updated: nil) = new(event).to_h(updated)

    def initialize(event)
      @event = event
    end

    def to_h(_updated)
      round = @event.rounds.published.order(:number).includes(:results, pods: :seatings).last
      { tid: @event.slug, name: @event.name, state: @event.state,
        starts_at: Feeds.iso(@event.start_time), ends_at: Feeds.iso(@event.end_time),
        players: @event.playing_participants_count, round: round && Feeds.round_label(round),
        timerEnd: Feeds.timer_end(round) }
    end
  end
end
