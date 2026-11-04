# frozen_string_literal: true

module TournamentsHelper # rubocop:disable Metrics/ModuleLength
  CURRENCY_SYMBOLS = {
    euro: "€",
    dollar: "$"
  }.with_indifferent_access.freeze

  NUMBER_CURRENCY_OPTIONS = {
    euro: { unit: "€", separator: ",", delimiter: " ", format: "%n %u" },
    dollar: { unit: "$", separator: ".", delimiter: ",", format: "%u%n" }
  }.with_indifferent_access.freeze

  STATE_TRANSITION_MAP = {
    draft: { name: "Make Draft", icon: "pencil" },
    registration_open: { name: "Open Registrations", icon: "megaphone" },
    registration_closed: { name: "Close Registrations", icon: "lock" },
    swiss: { name: "Move to Swiss stage", icon: "ranking" },
    single_elimination: { name: "Move to Single Elimination Stage", icon: "tree-structure" },
    finished: { name: "Finish", icon: "trophy" },
    canceled: { name: "Cancel", icon: "trash" }
  }.with_indifferent_access.freeze

  POD_STATUS_TONES = {
    playing: :ink, pending: :muted, review: :muted, disputed: :danger, completed: :accent
  }.freeze

  def pod_status_tone(status)
    POD_STATUS_TONES.fetch(status)
  end

  def pod_status_chip(pod)
    status = pod.report_status
    status_chip(pod_status_tone(status)) { t("rounds.status.#{status}") }
  end

  # Seat (seating order) of each participant at the pod, by participant id.
  def pod_seats(pod)
    pod.seatings.to_h { |seating| [seating.event_participant_id, seating.order] }
  end

  # "Reported by seat 2 · 14:05" (1v1: "Reported by <name> · 14:05", seats are random), nil when no player reported.
  def pod_reported_line(pod)
    seat = pod_seats(pod)[pod.reported_by_participant_id]
    return if seat.nil? || pod.reported_at.nil?

    time = l(pod.reported_at, format: "%H:%M")
    return t("rounds.reported_by", seat: seat, time: time) unless pod.event.one_v_one?

    t("rounds.reported_by_player", name: pod_names(pod)[pod.reported_by_participant_id], time: time)
  end

  # "Confirmed: 1, 3" for the seats that confirmed the pending report (1v1: the players' names).
  def pod_confirmed_line(pod)
    one_v_one = pod.event.one_v_one?
    labels = (one_v_one ? pod_names(pod) : pod_seats(pod)).values_at(*pod.confirmations.keys).compact
    return if labels.empty?

    if one_v_one then t("rounds.confirmed_by_players", names: labels.join(", "))
    else t("rounds.confirmed", seats: labels.sort.join(", "))
    end
  end

  # Name of each participant at the pod, by participant id.
  def pod_names(pod)
    pod.seatings.to_h { |seating| [seating.event_participant_id, seating.event_participant.name] }
  end

  # 1v1 score buttons as [label, "won-lost-drawn" form value] for the event's best-of-N.
  # Bo3 "1-0" is a match stopped on time: the unfinished game is a draw (1-0-1).
  WINNER_SCORE_OPTIONS = { 3 => [["2-0", "2-0-0"], ["2-1", "2-1-0"], ["1-0", "1-0-1"]],
                           1 => [["1-0", "1-0-0"]] }.freeze
  DRAW_SCORE_OPTIONS = { 3 => [["1-1", "1-1-1"], ["0-0", "0-0-1"]], 1 => [["0-0", "0-0-1"]] }.freeze
  ON_TIME_SCORE = "1-0-1"

  def winner_score_options(event) = WINNER_SCORE_OPTIONS.fetch(event.match_games)

  # Title/aria text for a score button: "1-0 (time)" for the bo3 match stopped on time, else the label.
  def score_option_title(label, value)
    value == ON_TIME_SCORE ? t("rounds.score_on_time", score: label) : label
  end

  def draw_score_options(event) = DRAW_SCORE_OPTIONS.fetch(event.match_games)

  def currency_options
    EventOrganizer::CURRENCIES.keys.map { |c| [CURRENCY_SYMBOLS[c], c] }
  end

  def top_cut_options(format = "multiplayer")
    [[t("organizer.no_cut"), 0]] + Tournaments::TopCut.sizes_for(format).map { |size| [t("organizer.top_cut_option", size: size), size] }
  end

  def format_options
    Event::FORMATS.map { |format| [t("organizer.format_options.#{format}"), format] }
  end

  def match_games_options
    Event::MATCH_GAMES.sort.reverse.map { |games| [t("organizer.match_games_options.bo#{games}"), games] }
  end

  def pairing_mode_options
    Event::PAIRING_MODES.map { |mode| [t("organizer.pairing_modes.#{mode}"), mode] }
  end

  # Default points per format, for the form to switch untouched points with the format.
  def format_points_defaults
    { "multiplayer" => Event.column_defaults.slice(*Event::POINT_ATTRIBUTES.map(&:to_s)),
      "one_v_one" => Event::ONE_V_ONE_POINTS.stringify_keys }
  end

  def result_confirmation_options
    Event::RESULT_CONFIRMATIONS.map { |value| [t("organizer.result_confirmation_options.#{value}"), value] }
  end

  def top_cut_timeout_rule_options
    Event::TOP_CUT_TIMEOUT_RULES.map { |value| [t("organizer.top_cut_timeout_rule_options.#{value}"), value] }
  end

  # nil below 4 players (no structure to suggest yet).
  def structure_suggestion(tournament)
    players = tournament.playing_participants_count
    return if players < Tournament::PREFERRED_POD_SIZE

    suggested = Tournaments::Structure.suggested(players, format: tournament.format)
    rounds = suggested[:swiss_rounds]
    cut = suggested[:top_cut_size]
    t("organizer.#{structure_suggestion_key(rounds, cut)}", players: players, rounds: rounds, cut: cut)
  end

  # No swiss rounds: a 1v1 straight single elimination.
  def structure_suggestion_key(rounds, cut)
    if rounds.zero? then "structure_suggestion_elimination_only"
    elsif cut.zero? then "structure_suggestion_no_cut"
    else "structure_suggestion"
    end
  end

  # Times in seats 1-4 as "2·1·1·1", plus seat 5 when any player in the standings sat there.
  def seat_counts_label(seats, seat_five: false)
    seats.values_at(*(1..(seat_five ? 5 : 4))).join("·")
  end

  # Seat history as four (or five) 18 px cells: the count when the player has sat there (accent),
  # else the seat number dimmed.
  def seat_grid(seats, seat_five: false)
    label = seat_counts_label(seats, seat_five: seat_five)
    tag.span(class: "inline-flex gap-0.5 align-middle", title: label, "aria-label": label, role: "img") do
      (1..(seat_five ? 5 : 4)).each do |seat|
        count = seats[seat].to_i
        concat tag.span(count.positive? ? count : seat,
                        class: ["inline-flex size-[18px] items-center justify-center rounded-[3px] font-display",
                                "text-[10px] font-semibold",
                                count.positive? ? "bg-accent/20 text-accent" : "bg-surface-raised text-muted"])
      end
    end
  end

  # "66.7%", or "–" before the player has a real game.
  def win_rate_label(rate)
    rate.nil? ? "–" : number_to_percentage(rate * 100, precision: 1)
  end

  # True when anyone in the list sat in seat 5 of a swiss pod.
  def seat_five?(participants)
    participants.any? { |participant| participant.seat_counts[5].positive? }
  end

  # A 1v1 rate (OMW, GW, OGW) as "66.7%".
  def rate_label(rate)
    number_to_percentage(rate * 100, precision: 1)
  end

  def number_to_currency_options(currency)
    NUMBER_CURRENCY_OPTIONS[currency]
  end

  def transition_for(state:)
    tag.span(class: "inline-flex items-center") do
      concat icon(STATE_TRANSITION_MAP[state][:icon], class: "me-2")
      concat STATE_TRANSITION_MAP[state][:name]
    end
  end
end
