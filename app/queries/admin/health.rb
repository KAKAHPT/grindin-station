# frozen_string_literal: true

module Admin
  # Tournament-day health: one row per ongoing tournament or league, for its latest round. Four queries in all.
  class Health
    Row = Data.define(:event, :round_number, :judge_calls, :disputed, :pending, :review, :late)

    def self.call = new.call

    def call
      events = ongoing_events
      return [] if events.empty?

      rounds = latest_rounds(events)
      pods = pod_counts(rounds.values.map(&:id))
      calls = JudgeCall.open_or_acknowledged.where(event_id: events.map(&:id)).group(:event_id).count
      events.map { |event| row(event, rounds[event.id], pods, calls) }
    end

    private

    # One query for both kinds (two similar ones would read as an N+1 to Prosopite).
    def ongoing_events
      Event.where(id: Tournament.ongoing.select(:id)).or(Event.where(id: League.ongoing.select(:id)))
        .order(:start_time).to_a
    end

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
      return false unless round&.started_at && round.finished_at.nil? && round.respond_to?(:duration)

      duration = round.duration
      duration.present? && Time.current > round.started_at + duration + extra_minutes.minutes
    end
  end
end
