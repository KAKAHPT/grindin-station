# frozen_string_literal: true

# The old public round page (/tournaments/:id/rounds/:id) now lives on the event's pairings (/t/:slug/pairings).
class RoundsController < ApplicationController
  include PublicEvent

  skip_before_action :require_authentication, only: :show

  def show
    event = ensure_public!(Tournament.find(params[:tournament_id]))
    round = event.rounds.published.find(params[:id])
    redirect_to play_pairings_path(event.slug, round: round.number, locale: params[:locale])
  end
end
