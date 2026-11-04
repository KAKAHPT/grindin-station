# frozen_string_literal: true

class CircuitsController < ApplicationController
  skip_before_action :require_authentication

  # Draft and canceled events are left out of the lists and the counts.
  def index
    @circuits = Circuit.includes(:event_organizer).page(params[:page])
    ids = @circuits.map(&:id)
    @tournament_counts = Tournament.visible.where(circuit_id: ids).group(:circuit_id).count
    @league_counts = League.visible.where(circuit_id: ids).group(:circuit_id).count
  end

  def show
    @circuit = Circuit.preload(circuit_standings: :player).find(params[:id])
    @tournaments = @circuit.tournaments.visible.preload(:rounds).load
    @leagues = @circuit.leagues.visible.preload(:rounds).load
  end
end
