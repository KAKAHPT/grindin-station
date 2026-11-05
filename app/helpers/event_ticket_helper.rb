# frozen_string_literal: true

# The pieces shared by the event tickets (shared/_event_ticket, 4C) and the landing's featured tickets
# (shared/_featured_ticket, 4B): link, cover, format line, organizer, state line and the Register button.
module EventTicketHelper
  # A tournament opens at /t/:slug, a league at /leagues/:id.
  def ticket_href(event)
    locale = params[:locale]
    event.is_a?(League) ? league_path(event, locale: locale) : play_event_path(event.slug, locale: locale)
  end

  # The cover as a resized variant, or one of the landing card arts picked from the slug.
  def ticket_banner(event, size: 480)
    if event.cover.attached? && event.cover.representable?
      rails_representation_path(event.cover.representation(resize_to_limit: [size, size]), only_path: true)
    else
      image_path("landing/c#{(Zlib.crc32(event.slug) % 48) + 1}.jpg")
    end
  end

  # "Lisboa · cEDH · pods of four · 5 Swiss rounds · Top 10 · 10,00 €"
  def ticket_line(event)
    safe_join([ticket_city(event), event_format_label(event), *ticket_structure(event), ticket_price(event)].compact,
              " · ")
  end

  # The last part of the address ("Rua Augusta, Lisboa" gives "Lisboa"), or nil.
  def ticket_city(event) = event.address.to_s.split(",").last.to_s.strip.presence

  # The swiss rounds and the top cut, when set.
  def ticket_structure(event)
    rounds = event.swiss_rounds_count.to_i
    cut = event.top_cut_size.to_i
    [(t("organizer.shell.swiss_rounds", count: rounds) if rounds.positive?),
     (t("organizer.top_cut_option", size: cut) if cut.positive?)]
  end

  def ticket_price(event)
    tag.span(tournament_price(event), class: "whitespace-nowrap") if event.price.to_d.zero? || event.currency
  end

  # The organizer's initials and name (a link to the organizer page when the user has a handle), or nil without one.
  def ticket_organizer(event)
    user = event.event_organizer&.user
    return unless user&.name

    tag.p(class: "lp-evr-org") do
      safe_join([tag.i(user.name.split.first(2).map { |word| word[0] }.join.upcase, "aria-hidden": "true"),
                 ticket_organizer_name(user)])
    end
  end

  # The organizer's name, linked to /o/:handle when they have one.
  def ticket_organizer_name(user)
    return user.name unless user.handle

    link_to user.name, organizer_profile_path(user.handle, locale: params[:locale])
  end

  # Large tickets (/events): the start time and the full address on one line.
  def ticket_when_where(event)
    safe_join([l(event.start_time, format: t("play.events.time_format")), event.address.presence].compact, " · ")
  end

  # Large tickets: the first 160 characters of the description, markdown marks stripped; nil without one.
  def ticket_excerpt(event)
    text = event.description.to_s.gsub(/[*_#>`\[\]]/, "").squish
    truncate(text, length: 160, separator: " ") if text.present?
  end

  # "12 of 48 enrolled" or "12 enrolled".
  def ticket_enrolled(event, enrolled)
    max = event.maximum_participants
    label = max.infinite? ? t("landing.upcoming.enrolled") : t("landing.upcoming.of_max", max: max)
    safe_join([tag.b(enrolled), label])
  end

  # Full while registration is open: the chip reads Sold out and Register becomes Join waiting list.
  def ticket_sold_out?(event, sold_out)
    sold_out && event.registration_open?
  end

  def ticket_tone(event, sold_out)
    ticket_sold_out?(event, sold_out) ? :warn : EventsHelper::EVENT_STATE_TONES.fetch(event.state)
  end

  # The state as a small line under the organizer ("Sold out", "Registration open", "Swiss round 2"); sold out in
  # the warn tone, everything else muted.
  def ticket_state_line(event, sold_out)
    sold = ticket_sold_out?(event, sold_out)
    text = sold ? t("play.events.state.sold_out") : event_state_label(event, event.latest_published_round_number)
    tag.p(text, class: "lp-evr-state", data: { state_line: (sold ? "sold_out" : event.state), tone: ("warn" if sold) })
  end

  # Register while a tournament's registration is open; Join waiting list once it is full (when the event keeps
  # one; a full event without a waiting list shows none).
  def ticket_register_button(event, sold_out)
    return unless event.is_a?(Tournament) && event.registration_open?

    if ticket_sold_out?(event, sold_out)
      return unless event.waitlist_enabled

      label = t("play.events.join_waitlist")
    else
      label = t("landing.upcoming.register")
    end
    link_to label, ticket_href(event), class: button_classes(:light, size: :xs), data: { register: true }
  end
end
