# frozen_string_literal: true

# /my-events: the events the signed-in player is registered in, as the same tickets as /events: running now,
# upcoming, then past (latest first).
class MyEventsController < ApplicationController
  include EventTickets

  LIMIT = 100

  def index
    events = my_events
    @running, rest = events.partition { |event| running?(event) }
    @past, @upcoming = rest.partition { |event| event.finished? || event.end_time.past? }
    @upcoming.reverse!
    @enrolled = enrolled_counts(events)
  end

  private

  def my_events
    ticket_preload(visible_events.for_player(current_user.player)).order(start_time: :desc).limit(LIMIT).to_a
  end

  def running?(event) = event.is_a?(League) ? event.playing? : event.ongoing?
end
