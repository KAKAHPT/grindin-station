# frozen_string_literal: true

# /events: the public tournaments and leagues (upcoming by default, ?filter=past) as a grid of tickets or a list
# (?view=, remembered in a cookie), narrowed by the filter bar (search, season, country, organizer, format), under
# the featured strip and the viewer's own events running now.
class EventsController < ApplicationController
  include EventTickets

  skip_before_action :require_authentication

  VIEWS = %w[grid list].freeze
  FEATURED_LIMIT = 6

  def index
    @past = params[:filter] == "past"
    @view = events_view
    @filters = ticket_filters
    @filter_options = ticket_filter_options
    @featured = featured_tickets
    ongoing_tournaments = ongoing_tickets(Tournament)
    ongoing_leagues = ongoing_tickets(League)
    @ongoing = ongoing_tournaments + ongoing_leagues
    # An event shown under "running now" is not listed again below it.
    @tournaments = ticket_scope(Tournament, past: @past, except: ongoing_tournaments, filters: @filters)
    @leagues = ticket_scope(League, past: @past, except: ongoing_leagues, filters: @filters)
    @enrolled = enrolled_counts(@tournaments.to_a + @leagues.to_a + @ongoing + @featured)
  end

  private

  # ?view= wins (an unknown value is the grid) and is remembered for a year; without it, the cookie or the grid.
  def events_view
    return VIEWS.include?(cookies[:events_view]) ? cookies[:events_view] : "grid" unless params.key?(:view)

    view = VIEWS.include?(params[:view]) ? params[:view] : "grid"
    cookies[:events_view] = { value: view, expires: 1.year }
    view
  end

  # Featured visible events running now or upcoming, soonest first.
  def featured_tickets
    ticket_preload(visible_events.where(featured: true).where(end_time: Time.current..).order(:start_time))
      .limit(FEATURED_LIMIT).to_a
  end
end
