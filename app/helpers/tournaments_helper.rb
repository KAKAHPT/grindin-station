# frozen_string_literal: true

module TournamentsHelper
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

  # "Reported by seat 2 · 14:05", nil when no player reported.
  def pod_reported_line(pod)
    seat = pod_seats(pod)[pod.reported_by_participant_id]
    return if seat.nil? || pod.reported_at.nil?

    t("rounds.reported_by", seat: seat, time: l(pod.reported_at, format: "%H:%M"))
  end

  # "Confirmed: 1, 3" for the seats that confirmed the pending report.
  def pod_confirmed_line(pod)
    seats = pod_seats(pod).values_at(*pod.confirmations.keys).compact.sort
    t("rounds.confirmed", seats: seats.join(", ")) if seats.any?
  end

  def currency_options
    EventOrganizer::CURRENCIES.keys.map { |c| [CURRENCY_SYMBOLS[c], c] }
  end

  def top_cut_options
    [[t("organizer.no_cut"), 0]] + Tournaments::TopCut::SIZES.map { |size| [t("organizer.top_cut_option", size: size), size] }
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

    suggested = Tournaments::Structure.suggested(players)
    if suggested[:top_cut_size].zero?
      t("organizer.structure_suggestion_no_cut", players: players, rounds: suggested[:swiss_rounds])
    else
      t("organizer.structure_suggestion", players: players, rounds: suggested[:swiss_rounds],
                                          cut: suggested[:top_cut_size])
    end
  end

  # Times in seats 1-4 as "2·1·1·1", plus seat 5 when any player in the standings sat there.
  def seat_counts_label(seats, seat_five: false)
    seats.values_at(*(1..(seat_five ? 5 : 4))).join("·")
  end

  # One bar per seat, lit when the player has sat there; the counts go in the title / aria-label.
  def seat_pips(seats, seat_five: false)
    label = seat_counts_label(seats, seat_five: seat_five)
    tag.span(class: "inline-flex gap-1 align-middle", title: label, "aria-label": label, role: "img") do
      seats.values_at(*(1..(seat_five ? 5 : 4))).each do |count|
        concat tag.span(class: ["h-1.5 w-4 rounded-full", count.to_i.positive? ? "bg-accent" : "bg-line"])
      end
    end
  end

  # Ranks inside the top cut sit in an accent disc; the rest are muted text.
  def standings_rank(rank, tournament)
    cut = tournament.top_cut_size.to_i
    if cut.positive? && rank <= cut
      tag.span(rank, class: "inline-flex size-7 items-center justify-center rounded-full bg-accent/15 " \
                            "text-accent font-display text-sm font-semibold")
    else
      tag.span(rank, class: "inline-flex size-7 items-center justify-center text-muted font-display text-sm")
    end
  end

  # True when anyone in the list sat in seat 5 of a swiss pod.
  def seat_five?(participants)
    participants.any? { |participant| participant.seat_counts[5].positive? }
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
