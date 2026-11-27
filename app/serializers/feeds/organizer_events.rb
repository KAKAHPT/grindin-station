# frozen_string_literal: true

module Feeds
  # {organizer: {handle, name}, events: [...]}, each event
  # {slug, kind ("tournament" or "league"), name, url, state, dateTba, starts_at, ends_at, address, city, players,
  # capacity, free, price, currency, format, gameFormat, swissRounds, topCut, cover}.
  # A date still to be announced leaves starts_at/ends_at nil (the stored date only orders the list). capacity is nil
  # without a maximum; cover is an absolute URL (the event's own cover, else the landing card art the site shows).
  class OrganizerEvents
    include Rails.application.routes.url_helpers

    def self.call(organizer, events:, base_url:) = new(organizer, base_url).to_h(events)

    def initialize(organizer, base_url)
      @organizer = organizer
      @base_url = base_url
    end

    def to_h(events)
      enrolled = EventParticipant.enrolled.where(event_id: events.map(&:id)).group(:event_id).count
      { organizer: { handle: @organizer.user.handle, name: @organizer.name },
        events: events.map { |event| event_keys(event, enrolled.fetch(event.id, 0)) } }
    end

    private

    def event_keys(event, players)
      league = event.is_a?(League)
      { slug: event.slug, kind: league ? "league" : "tournament", name: event.name,
        url: @base_url + (league ? league_path(event) : play_event_path(event.slug)), state: event.state }
        .merge(date_keys(event), place_keys(event), entry_keys(event, players), format_keys(event),
               cover: cover_url(event))
    end

    def date_keys(event)
      return { dateTba: true, starts_at: nil, ends_at: nil } if event.date_tba

      { dateTba: false, starts_at: Feeds.iso(event.start_time), ends_at: Feeds.iso(event.end_time) }
    end

    def place_keys(event)
      address = event.address.to_s.squish.presence
      { address: address, city: address&.split(",")&.last&.strip.presence, country: event.country }
    end

    def entry_keys(event, players)
      max = event.maximum_participants
      { players: players, capacity: (max.to_i if max.finite? && max.positive?), free: event.free?,
        price: (event.price.to_d.to_s("F") unless event.free?), currency: event.currency }
    end

    def format_keys(event)
      { format: event.format, gameFormat: event.game_format,
        swissRounds: event.swiss_rounds_count.to_i.nonzero?, topCut: event.top_cut_size.to_i.nonzero? }
    end

    def cover_url(event)
      path = if event.cover.attached? && event.cover.representable?
               rails_representation_path(event.cover.representation(resize_to_limit: [960, 960]), only_path: true)
             else
               ActionController::Base.helpers.image_path("landing/c#{(Zlib.crc32(event.slug) % 48) + 1}.jpg")
             end
      @base_url + path
    end
  end
end
