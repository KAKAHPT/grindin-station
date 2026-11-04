# frozen_string_literal: true

class LeaguesController < ApplicationController
  include PublicEvent
  include EventTickets

  skip_before_action :require_authentication

  # Public leagues as tickets (upcoming by default, ?filter=past) and the viewer's own running now.
  def index
    @past = params[:filter] == "past"
    @ongoing = ongoing_tickets(League)
    @leagues = ticket_scope(League, past: @past, except: @ongoing)
    @enrolled = enrolled_counts(@leagues.to_a + @ongoing)
  end

  def show
    scope = League.preload(:rounds, cover_attachment: :blob, event_participants: [:results, { player: :user }])
    @league = ensure_public!(scope.find(params[:id]))
  end
end
