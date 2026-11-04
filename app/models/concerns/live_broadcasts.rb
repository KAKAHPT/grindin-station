# frozen_string_literal: true

# Turbo Stream names of the live pages ("my table" and the organizer round page). Broadcasts are
# rendered outside any request, so each stream carries the viewer's locale and is rendered once per
# locale: a page only ever receives copy in its own language.
module LiveBroadcasts
  extend self

  # One stream per participant: their table is rendered for them (seat, "You", what they may do).
  def table_stream(event, participant, locale = I18n.locale)
    [event, participant, locale.to_s]
  end

  # Staff on the round page, whatever their role: only role-free content goes here.
  def round_stream(round_id, locale = I18n.locale)
    "round:#{round_id}:#{locale}"
  end

  # Public pairings page (/t/:slug/pairings), whatever round it shows.
  def pairings_stream(event_id, locale = I18n.locale)
    "pairings:#{event_id}:#{locale}"
  end

  def each_locale
    I18n.available_locales.each { |locale| I18n.with_locale(locale) { yield locale } }
  end

  # Morph-refreshes every round page open on the round (the page that made the change is skipped).
  def refresh_round(round_id, request_id: nil)
    each_locale do |locale|
      Turbo::StreamsChannel.broadcast_refresh_to(round_stream(round_id, locale), request_id: request_id)
    end
  end

  # Morph-refreshes every open public pairings page of the event.
  def refresh_pairings(event_id, request_id: nil)
    each_locale do |locale|
      Turbo::StreamsChannel.broadcast_refresh_to(pairings_stream(event_id, locale), request_id: request_id)
    end
  end

  # Replaces the participant's table (#my_table) with its current state.
  def broadcast_table(state)
    each_locale do |locale|
      Turbo::StreamsChannel.broadcast_replace_to(
        table_stream(state.event, state.participant, locale),
        target: "my_table", partial: "play/tables/table", locals: state.locals.merge(locale: locale)
      )
    end
  end
end
