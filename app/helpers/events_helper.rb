# frozen_string_literal: true

# The public event pages (/t/:slug, /pairings, /standings, /me): state chip and the event header card.
module EventsHelper
  EVENT_STATE_TONES = {
    draft: :warn, registration_open: :ok, registration_closed: :warn, swiss: :info,
    single_elimination: :info, finished: :info, canceled: :bad, play: :info, finals: :info
  }.with_indifferent_access.freeze

  # "Registration open", "Swiss round 3", "Top 16", ...; round_number is the latest published round.
  def event_state_chip(event, round_number)
    desk_chip(EVENT_STATE_TONES.fetch(event.state)) { event_state_label(event, round_number) }
  end

  def event_state_label(event, round_number)
    case event.state
    when "swiss" then t("play.events.state.swiss", number: round_number || 1)
    when "single_elimination" then t("play.events.state.single_elimination", size: event.top_cut_size)
    else t("play.events.state.#{event.state}")
    end
  end

  # "cEDH · pods of four" or "Legacy · Bo3".
  def event_format_label(event)
    return play_label(event.play) unless event.one_v_one?

    t("play.events.format_badge", game_format: play_label(event.play), games: event.match_games)
  end

  # "cEDH · pods of four", "Legacy", "Other 1v1": one of Event::PLAYS.
  def play_label(play)
    t("play.formats.#{play}")
  end

  # Header eyebrow: "Swiss round 3 · cEDH · pods of four · live" (live only while a round is running); "Sold out"
  # in place of "Registration open" once the enrolled players fill the maximum.
  def play_eyebrow(event, round, players = nil)
    sold_out = event.registration_open? && players && event.sold_out?(players)
    state = sold_out ? t("play.events.state.sold_out") : event_state_label(event, round&.number)
    parts = [state, event_format_label(event)]
    parts << t("play.header.live") if round&.started? && round.finished_at.nil?
    parts.join(" · ")
  end

  # Header line: "4 Nov 2026 · Lisboa · 16 players" (the city is the last part of the address).
  def play_info_line(event, players)
    city = event.address.to_s.split(",").last.to_s.strip.presence
    [(l(event.start_time, format: "%-d %b %Y") if event.start_time), city, t("play.header.players", count: players)]
      .compact.join(" · ")
  end

  # About card format line: "cEDH · pods of four · 4 Swiss rounds · Swiss pods · Byes · Top 4 · 80 min rounds".
  def play_format_line(event)
    swiss, cut = tournament_structure(event).values_at(:swiss, :cut).map(&:to_i)
    [event_format_label(event), (t("organizer.shell.swiss_rounds", count: swiss) if swiss.positive?),
     pairing_mode_name(event), (uneven_field_name(event) if event.byes?),
     cut.positive? ? t("organizer.top_cut_option", size: cut) : t("organizer.no_cut"),
     t("play.header.round_minutes", minutes: event.round_minutes)].compact.join(" · ")
  end
end
