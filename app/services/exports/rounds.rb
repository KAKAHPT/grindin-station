# frozen_string_literal: true

module Exports
  # Every published or closed round, one row per seat; byes and walkovers follow with no table or seat.
  class Rounds
    HEADERS = %w[round table seat player email result gamesWon gamesLost gamesDrawn].freeze

    def self.call(event) = new(event).to_csv

    def initialize(event)
      @event = event
      @by_id = event.event_participants.includes(player: :user).index_by(&:id)
    end

    def to_csv
      rounds = @event.rounds.published.or(@event.rounds.finished).order(:number).includes(:results, pods: :seatings)
      CsvFile.generate(HEADERS, rounds.flat_map { |round| rows(round) })
    end

    private

    def rows(round)
      results = round.results.index_by(&:event_participant_id)
      places(round, results.keys).map { |*place, id| row(place, id, results[id]) }
    end

    # [round, table, seat, participant id]: seats in table order, then the unseated results by name.
    def places(round, result_ids)
      label = label(round)
      seatings = round.pods.sort_by(&:number).flat_map(&:seatings)
      unseated = sort_by_name(result_ids - seatings.map(&:event_participant_id))
      seatings.map { |seating| [label, seating.pod.number, seating.order, seating.event_participant_id] } +
        unseated.map { |id| [label, nil, nil, id] }
    end

    def sort_by_name(ids) = ids.sort_by { |id| @by_id.fetch(id).name }

    def row(place, participant_id, result)
      participant = @by_id.fetch(participant_id)
      [*place, participant.name, participant.player.reporting_email, result_name(result, place[1]),
       *(result&.games || [nil, nil, nil])]
    end

    # An Advance without a table in a swiss round is a bye; otherwise the result type.
    def result_name(result, table)
      return unless result
      return "bye" if result.is_a?(Advance) && table.nil? && result.round.is_a?(SwissRound)

      result.type.downcase
    end

    # Cut rounds by their cut name ("Semi-Finals"), else "Top N" like the feeds.
    def label(round)
      return round.number.to_s unless round.is_a?(SingleEliminationRound)

      (@event.single_elimination_round_name(round.number) if @event.respond_to?(:single_elimination_round_name)) ||
        Feeds.round_label(round)
    end
  end
end
