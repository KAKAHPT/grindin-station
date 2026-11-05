# frozen_string_literal: true

# The organizer tournament page shell: state chip, event header (eyebrow, info line, state action), route tabs.
module OrganizerShellHelper
  # "Registration open", "Swiss round 2", "Top 4", ... as a flat chip; swiss uses the latest round number.
  def organizer_state_chip(tournament)
    tone = EventsHelper::EVENT_STATE_TONES.fetch(tournament.state)
    tag.span(data: { state_chip: tournament.state }) { desk_chip(tone) { organizer_state_label(tournament) } }
  end

  def organizer_state_label(tournament)
    case tournament.state
    when "swiss"
      t("play.events.state.swiss", number: tournament.rounds.map(&:number).max || 1)
    when "single_elimination"
      # The counter cache, not a count query: the label shows on every card of the list.
      suggested = Tournaments::Structure.suggested(tournament.event_participants_count, format: tournament.format)
      size = tournament.top_cut_size || suggested[:top_cut_size]
      t("play.events.state.single_elimination", size: size)
    else t("play.events.state.#{tournament.state}")
    end
  end

  # "Tournament · Registration open · Legacy · Bo3" (the game format for 1v1)
  def tournament_eyebrow(tournament)
    format = tournament.one_v_one? ? play_label(tournament.play) : t("organizer.format_options.#{tournament.format}")
    parts = [t("organizer.shell.tournament"), organizer_state_label(tournament), format]
    parts << t("organizer.shell.best_of", games: tournament.match_games) if tournament.one_v_one?
    parts.join(" · ")
  end

  # "4 Nov 2026, 14:15 – 22:15 · Lisboa · Free entry · 4 Swiss rounds · Swiss pods · Top 4" (no pods for 1v1)
  def tournament_info_line(tournament, structure = tournament_structure(tournament))
    [tournament_when(tournament), tournament.address.presence, tournament_price(tournament),
     t("organizer.shell.swiss_rounds", count: structure[:swiss]), pairing_mode_name(tournament),
     structure[:cut].positive? ? t("organizer.top_cut_option", size: structure[:cut]) : t("organizer.no_cut")]
      .compact.join(" · ")
  end

  # "Power pods"; nil for 1v1 (always paired the same way).
  def pairing_mode_name(event)
    t("organizer.pairing_modes.#{event.pairing_mode}") unless event.one_v_one?
  end

  # "Byes"; nil for 1v1 (2-player pods, odd field always gets a bye).
  def uneven_field_name(event)
    t("organizer.uneven_fields.#{event.uneven_field}") unless event.one_v_one?
  end

  # Swiss rounds and top cut as set, else as suggested for the field (one count query).
  def tournament_structure(tournament)
    suggested = Tournaments::Structure.suggested(tournament.playing_participants_count, format: tournament.format)
    { swiss: tournament.swiss_rounds_count || suggested[:swiss_rounds],
      cut: tournament.top_cut_size || suggested[:top_cut_size] }
  end

  def tournament_when(tournament)
    return if tournament.start_time.nil?

    start = l(tournament.start_time, format: "%-d %b %Y, %H:%M")
    return start if tournament.end_time.nil?

    same_day = tournament.end_time.to_date == tournament.start_time.to_date
    "#{start} – #{l(tournament.end_time, format: same_day ? '%H:%M' : '%-d %b %Y, %H:%M')}"
  end

  def tournament_short_date(tournament)
    tournament.start_time && l(tournament.start_time, format: "%-d %b, %H:%M")
  end

  def tournament_price(tournament)
    return t("play.events.free") if tournament.price.to_d.zero?

    number_to_currency(tournament.price, number_to_currency_options(tournament.currency))
  end

  # The one state change offered in the header before the swiss (the round page moves the swiss on;
  # Cancel event lives in Settings).
  def tournament_next_state(tournament)
    return unless tournament.state_for_database < Tournament.states[:swiss]

    tournament.available_states.keys.find { |state| state != "canceled" }
  end

  # Tab => roles that may open it (nil: every staff role; :owner: the event's owner only).
  TAB_ROLES = { overview: nil, roster: nil, rounds: nil, judge: %w[organizer judge], staff: :owner,
                settings: %w[organizer] }.freeze

  # The route tabs the viewer's role can open; Rounds is disabled until there is a round.
  def tournament_tabs(tournament, role:, active:, open_calls:)
    TAB_ROLES.filter_map do |key, roles|
      next unless tab_allowed?(tournament, roles, role)

      tab = { key: key, path: tab_path(tournament, key), label: t("organizer.shell.tabs.#{key}"),
              active: key == active }
      key == :judge ? tab.merge(badge: open_calls.nonzero?, badge_data: { judge_calls_count: true }) : tab
    end
  end

  def tab_allowed?(tournament, roles, role)
    return true if roles.nil?
    return roles.include?(role) unless roles == :owner

    tournament.event_organizer_id.present? && tournament.event_organizer_id == current_user.event_organizer&.id
  end

  def tab_path(tournament, key)
    return rounds_tab_path(tournament) if key == :rounds

    { overview: -> { organizer_tournament_path(tournament) },
      roster: -> { organizer_tournament_event_participants_path(tournament, layout: "application") },
      judge: -> { organizer_tournament_judge_calls_path(tournament) },
      staff: -> { organizer_tournament_staff_index_path(tournament) },
      settings: -> { edit_organizer_tournament_path(tournament) } }.fetch(key).call
  end

  def rounds_tab_path(tournament)
    latest = tournament.rounds.max_by(&:number)
    latest && organizer_tournament_round_path(tournament, latest)
  end

  # The tab of the current page, from the controller and action.
  def tournament_active_tab
    case controller_name
    when "event_participants" then :roster
    when "rounds" then :rounds
    when "judge_calls" then :judge
    when "staff" then :staff
    else action_name.in?(%w[edit update]) ? :settings : :overview
    end
  end
end
