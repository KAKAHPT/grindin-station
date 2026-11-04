# frozen_string_literal: true

# Public JSON feeds read by the cEDH PT OBS stream kit (/api/v1/events/:slug/...). The keys follow the
# TopDeck relay the kit read before; no decklists or links ever, commanders only when the event shows them.
module Feeds
  extend self

  LAST_CHANGE_SQL = <<~SQL.squish
    SELECT GREATEST(
      (SELECT updated_at FROM events WHERE id = :id),
      (SELECT MAX(updated_at) FROM event_participants WHERE event_id = :id),
      (SELECT MAX(updated_at) FROM rounds WHERE event_id = :id),
      (SELECT MAX(pods.updated_at) FROM pods JOIN rounds ON rounds.id = pods.round_id WHERE rounds.event_id = :id),
      (SELECT MAX(seatings.updated_at) FROM seatings JOIN pods ON pods.id = seatings.pod_id
         JOIN rounds ON rounds.id = pods.round_id WHERE rounds.event_id = :id),
      (SELECT MAX(results.updated_at) FROM results JOIN rounds ON rounds.id = results.round_id
         WHERE rounds.event_id = :id),
      (SELECT MAX(users.updated_at) FROM users JOIN players ON players.user_id = users.id
         JOIN event_participants ON event_participants.player_id = players.id WHERE event_participants.event_id = :id)
    )
  SQL

  # Latest change to anything a feed shows (the event, its participants and their users' names, rounds,
  # pods, seatings and results), in one query: the feeds' "updated" and the HTTP cache validator.
  def last_change(event)
    Event.connection.select_all(Event.sanitize_sql([LAST_CHANGE_SQL, { id: event.id }])).cast_values.first.utc
  end

  def commander(event, participant)
    event.show_commanders_in_standings ? participant.commander_text.to_s : ""
  end

  # The kit's round names: "1", "2"... for the swiss, "Top 16", "Top 4"... for the cut (players seated
  # plus those with a bye into the round). Reads the round's pods, seatings and results.
  def round_label(round)
    return round.number.to_s unless round.is_a?(SingleEliminationRound)

    seated = round.pods.flat_map { |pod| pod.seatings.map(&:event_participant_id) }
    byes = round.results.count { |result| result.is_a?(Advance) && seated.exclude?(result.event_participant_id) }
    "Top #{seated.size + byes}"
  end

  # Minutes of the round, or nil when it has no time limit (the final).
  def round_minutes(round)
    duration = round&.duration
    duration && (duration / 60).to_i
  end

  # When the clock of a running round ends, ISO 8601; nil before it starts, after it closes or without a limit.
  def timer_end(round)
    return unless round&.started_at && round.finished_at.nil? && round.duration

    (round.started_at + round.duration).utc.iso8601
  end

  def iso(time) = time&.utc&.iso8601

  # The relay's timestamps: whole epoch seconds, nil stays nil.
  def epoch(time) = time&.to_i
end
