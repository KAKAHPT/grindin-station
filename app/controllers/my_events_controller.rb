# frozen_string_literal: true

# /my-events: the events the signed-in player is registered in, as the same tickets as /events: running now,
# upcoming, then past (latest first). Each ticket carries the player's own actions: decklist and drop.
class MyEventsController < ApplicationController
  include EventTickets

  LIMIT = 100

  def index
    events = my_events
    @running, rest = events.partition { |event| running?(event) }
    @past, @upcoming = rest.partition { |event| event.finished? || event.end_time.past? }
    @upcoming.reverse!
    @enrolled = enrolled_counts(events)
    @participants = my_registrations(events)
    @league_tables = my_league_tables if Features.on?(:leagues)
  end

  private

  # The league tables the player sits at right now (waiting for players, or full and not settled).
  def my_league_tables
    seats = LeagueTableSeat.active.where(event_participant_id: @participants.values.map(&:id))
    LeagueTable.where(id: seats.select(:league_table_id), state: %w[waiting filled])
      .preload(:league, participants: { player: :user }).to_a
  end

  def my_registrations(events)
    EventParticipant.where(event_id: events.map(&:id), player: current_user.player).index_by(&:event_id)
  end

  def my_events
    ticket_preload(visible_events.for_player(current_user.player)).order(start_time: :desc).limit(LIMIT).to_a
  end

  def running?(event) = event.is_a?(League) ? event.playing? : event.ongoing?
end
