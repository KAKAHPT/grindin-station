# frozen_string_literal: true

module Exports
  # TopDeck pairings import for one round: one row per table, players in seat order. Byes are not tables.
  module Pairings
    HEADERS = %w[Table Player1 Player2 Player3 Player4 Player5].freeze

    def self.call(event, round:)
      names = event.event_participants.includes(player: :user).to_h { |participant| [participant.id, participant.name] }
      pods = round.pods.includes(:seatings).select { |pod| pod.seatings.any? }.sort_by(&:number)
      CsvFile.generate(HEADERS, pods.map { |pod| row(pod, names) })
    end

    # Padded to the header's width: a 4-player (or 1v1) table leaves the last players blank.
    def self.row(pod, names)
      row = [pod.number, *pod.seatings.map { |seating| names.fetch(seating.event_participant_id) }]
      row + ([nil] * (HEADERS.size - row.size))
    end
  end
end
