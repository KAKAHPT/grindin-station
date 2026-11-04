# frozen_string_literal: true

module Feeds
  # {tid, updated, latest, roundTime, rounds: [{round, tables: [{table, status, winner, draw, players: [...]}]}]}
  # Published rounds only; byes are not tables. A player's seed is their current overall rank.
  class Rounds
    def self.call(event, updated: Feeds.last_change(event)) = new(event).to_h(updated)

    def initialize(event)
      @event = event
      participants = EventParticipant.standings_for(event)
      @by_id = participants.index_by(&:id)
      @seeds =
        Standings.ranked(event, participants).each.with_index(1).to_h do |participant, rank|
          [participant.id, rank]
        end
    end

    def to_h(updated)
      rounds = @event.rounds.published.order(:number).includes(:results, pods: :seatings).to_a
      latest = rounds.last
      { tid: @event.slug, updated: Feeds.iso(updated), latest: latest && Feeds.round_label(latest),
        roundTime: Feeds.round_minutes(latest),
        rounds: rounds.map { |round| { round: Feeds.round_label(round), tables: tables(round) } } }
    end

    private

    def tables(round)
      round.pods.select { |pod| pod.seatings.any? }.sort_by(&:number).map { |pod| table(round, pod) }
    end

    def table(round, pod)
      results = pod.current_results
      draw = results.any?(Draw)
      { table: pod.number, status: status(round, pod, results), winner: winner(results, draw), draw: draw,
        players: pod.seatings.map { |seating| player(@by_id.fetch(seating.event_participant_id)) } }
    end

    def status(round, pod, results)
      report = pod.report_status
      if report == :completed then "Completed"
      elsif report == :playing && results.empty? && !round.started? then "Pending"
      else "Active"
      end
    end

    def winner(results, draw)
      won = results.find { |result| result.is_a?(Win) || result.is_a?(Advance) }
      if won then @by_id.fetch(won.event_participant_id).name
      elsif draw then "Draw"
      else ""
      end
    end

    def player(participant)
      { name: participant.name, commander: Feeds.commander(@event, participant), seed: @seeds[participant.id] }
    end
  end
end
