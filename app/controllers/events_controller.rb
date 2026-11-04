# frozen_string_literal: true

# /events: the public tournaments and leagues as tickets (upcoming by default, ?filter=past), and the viewer's own
# events running now.
class EventsController < ApplicationController
  include EventTickets

  skip_before_action :require_authentication

  def index
    @past = params[:filter] == "past"
    @tournaments = ticket_scope(Tournament, past: @past).page(params[:page]).load
    @leagues = ticket_scope(League, past: @past).page(params[:page]).load

    player = current_user&.player
    ongoing_tournaments = ticket_preload(Tournament.for_player(player).ongoing).to_a
    ongoing_leagues = ticket_preload(League.for_player(player).ongoing).to_a
    @ongoing = ongoing_tournaments + ongoing_leagues
    @enrolled = enrolled_counts(@tournaments.to_a + @leagues.to_a + @ongoing)
  end
end
