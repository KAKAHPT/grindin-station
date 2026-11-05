# frozen_string_literal: true

module Admin
  # Tournament-day health: one row per ongoing tournament or league, for its latest round. Five queries in
  # all: round durations come from the event columns, never from Round#duration (which queries per event).
  class Health
    Row = Data.define(:event, :round_number, :judge_calls, :disputed, :pending, :review, :late)

    def self.call = new.call

    def call
      events = ongoing_events
      return [] if events.empty?

      rounds = latest_rounds(events)
      pods = pod_counts(rounds.values.map(&:id))
      calls = per_event(JudgeCall.open_or_acknowledged, events)
      @enrolled = per_event(EventParticipant.enrolled, events)
      events.map { |event| row(event, rounds[event.id], pods, calls) }
    end

    private

    # One query for both kinds (two similar ones would read as an N+1 to Prosopite).
    def ongoing_events
      Event.where(id: Tournament.ongoing.select(:id)).or(Event.where(id: League.ongoing.select(:id)))
        .order(:start_time).to_a
    end

    def per_event(scope, events) = scope.where(event_id: events.map(&:id)).group(:event_id).count

    def latest_rounds(events)
      by_id = events.index_by(&:id)
      Round.select("DISTINCT ON (event_id) rounds.*").where(event_id: by_id.keys).order(:event_id, number: :desc)
        .each { |round| round.association(:event).target = by_id[round.event_id] }
        .index_by(&:event_id)
    end

    # round_id => [disputed, pending, review, max extra_time]
    def pod_counts(round_ids)
      Pod.where(round_id: round_ids).group(:round_id)
        .pluck(:round_id, Arel.sql("COUNT(*) FILTER (WHERE disputed)"),
               Arel.sql("COUNT(*) FILTER (WHERE pending_result IS NOT NULL)"),
               Arel.sql("COUNT(*) FILTER (WHERE review_requested_at IS NOT NULL)"), Arel.sql("MAX(extra_time)"))
        .to_h { |round_id, *counts| [round_id, counts] }
    end

    def row(event, round, pods, calls)
      disputed, pending, review, extra = pods.fetch(round&.id, [0, 0, 0, 0])
      Row.new(event: event, round_number: round&.number, judge_calls: calls.fetch(event.id, 0),
              disputed: disputed, pending: pending, review: review, late: late?(round, extra.to_i))
    end

    def late?(round, extra_minutes)
      return false unless round&.started_at && round.finished_at.nil?

      minutes = round_minutes(round)
      minutes.present? && Time.current > round.started_at + (minutes + extra_minutes).minutes
    end

    # Same as SwissRound#duration / SingleEliminationRound#duration (nil for the last cut round). League rounds
    # (play rounds stay open for weeks) are never late.
    def round_minutes(round)
      event = round.event
      return unless event.is_a?(Tournament)

      case round
      when SwissRound then event.round_minutes
      when SingleEliminationRound then event.top_cut_round_minutes unless last_cut_round?(round, event)
      end
    end

    # Tournament#rounds_info's planned swiss rounds + cut stages, with the enrolled count from one grouped query.
    def last_cut_round?(round, event)
      suggested = Tournaments::Structure.suggested(@enrolled.fetch(event.id, 0), format: event.format)
      swiss = event.swiss_rounds_count || suggested[:swiss_rounds]
      cut = event.top_cut_size || suggested[:top_cut_size]
      stages = cut.positive? ? Tournaments::TopCut.for(cut, format: event.format).stages.size : 0
      round.number == swiss + stages
    end
  end
end
