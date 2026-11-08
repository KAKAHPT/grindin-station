# frozen_string_literal: true

module Tournaments
  # The top cut as the stages of the public bracket: one per single-elimination round of the cut, in order.
  # A stage already created carries its published round (tables and byes); a stage still to come has only
  # the number of tables it will have, so the page can draw them empty.
  module Bracket
    extend self

    Stage =
      Data.define(:number, :name, :round, :pods, :byes, :pod_count, :pod_size) do
        def upcoming? = round.nil?
        def running? = round&.started? && !round.past?
        def finished? = round&.past? || false
      end

    def stages_for(event)
      rounds = published_cut_rounds(event)
      first_number = event.number_of_swiss_rounds + 1
      pod_size = event.one_v_one? ? 2 : Event::PREFERRED_POD_SIZE

      (event.rounds_info.dig(:top, :pods) || []).each_with_index.map do |pod_count, index|
        number = first_number + index
        stage_for(event, number, rounds.find { |round| round.number == number }, pod_count, pod_size)
      end
    end

    private

    def stage_for(event, number, round, pod_count, pod_size)
      Stage.new(number: number, name: event.single_elimination_round_name(number), round: round,
                pods: round ? round.pods.sort_by(&:number) : [], byes: round ? byes_of(round) : [],
                pod_count: pod_count, pod_size: pod_size)
    end

    def published_cut_rounds(event)
      event.rounds.published.where(type: "SingleEliminationRound").order(:number)
        .preload(pods: [{ round: :results }, { seatings: { event_participant: { player: :user } } }]).to_a
    end

    def byes_of(round)
      round.byes.preload(event_participant: { player: :user }).sort_by { |bye| bye.event_participant.name }
    end
  end
end
