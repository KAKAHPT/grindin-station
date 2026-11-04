# frozen_string_literal: true

# /events: the public tournaments and leagues as tickets (upcoming by default, ?filter=past), and the viewer's own
# events running now.
class EventsController < ApplicationController
  include EventTickets

  skip_before_action :require_authentication

  def index
    @past = params[:filter] == "past"
    ongoing_tournaments = ongoing_tickets(Tournament)
    ongoing_leagues = ongoing_tickets(League)
    @ongoing = ongoing_tournaments + ongoing_leagues
    # An event shown under "running now" is not listed again below it.
    @tournaments = ticket_scope(Tournament, past: @past, except: ongoing_tournaments)
    @leagues = ticket_scope(League, past: @past, except: ongoing_leagues)
    @enrolled = enrolled_counts(@tournaments.to_a + @leagues.to_a + @ongoing)
  end
end
