# frozen_string_literal: true

class TournamentsController < ApplicationController
  include PublicEvent
  include EventTickets

  skip_before_action :require_authentication

  # Public tournaments as tickets (upcoming by default, ?filter=past) and the viewer's own running now.
  def index
    @past = params[:filter] == "past"
    @ongoing = ongoing_tickets(Tournament)
    @tournaments = ticket_scope(Tournament, past: @past, except: @ongoing)
    @enrolled = enrolled_counts(@tournaments.to_a + @ongoing)
  end

  # The event page lives at /t/:slug (every event has one). A hidden event is not found, as there.
  def show
    tournament = ensure_public!(Tournament.find(params[:id]))
    flash.keep # notices from enrol/cancel, which still redirect here
    redirect_to play_event_path(tournament.slug, locale: params[:locale])
  end
end
