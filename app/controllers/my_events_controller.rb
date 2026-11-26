# frozen_string_literal: true

# /my-events: the events the signed-in player is registered in, as the same tickets as /events: running now,
# upcoming, then past (latest first). Each ticket carries the player's own actions: decklist and drop. Above them,
# the events the user runs or works as staff, with the way into the organizer's side.
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
    load_extras
  end

  private

  # Beside the tickets: the league tables the player sits at and the events they run or work as staff.
  def load_extras
    @league_tables = my_league_tables if Features.on?(:leagues)
    @staffed = staffed_events
  end

  # The events the user runs or works as staff (owner, organizer, judge, scorekeeper, caster) and that are not
  # over, soonest first, each with their role: the way into the organizer's side of each.
  def staffed_events
    return [] unless current_user.staff?

    events = staffed_scope.order(:start_time).limit(LIMIT).to_a
    roles = current_user.event_staff.where(event_id: events.map(&:id)).pluck(:event_id, :role).to_h
    events.map { |event| [event, roles[event.id] || "organizer"] }
  end

  def staffed_scope
    over = Tournament.states.values_at("finished", "canceled")
    (Features.on?(:leagues) ? Event : Tournament).staffed_by(current_user).where.not(state: over)
  end

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
