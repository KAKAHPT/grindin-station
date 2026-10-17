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

  def currency_options
    EventOrganizer::CURRENCIES.keys.map { |c| [CURRENCY_SYMBOLS[c], c] }
  end

  def top_cut_options
    [[t("organizer.no_cut"), 0]] + Tournaments::TopCut::SIZES.map { |size| [t("organizer.top_cut_option", size:), size] }
  end

  def structure_suggestion(tournament)
    players = tournament.event_participants.size
    suggested = Tournaments::Structure.suggested(players)
    if suggested[:top_cut_size].zero?
      t("organizer.structure_suggestion_no_cut", players:, rounds: suggested[:swiss_rounds])
    else
      t("organizer.structure_suggestion", players:, rounds: suggested[:swiss_rounds], cut: suggested[:top_cut_size])
    end
  end

  # Times in seats 1-4 as "2·1·1·1", plus seat 5 when any player in the standings sat there.
  def seat_counts_label(seats, seat_five: false)
    seats.values_at(*(1..(seat_five ? 5 : 4))).join("·")
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
