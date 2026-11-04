# frozen_string_literal: true

class CircuitsController < ApplicationController
  include EventTickets

  skip_before_action :require_authentication

  # Draft and canceled events are left out of the lists and the counts.
  def index
    @circuits = Circuit.preload(event_organizer: :user).page(params[:page])
    ids = @circuits.map(&:id)
    @tournament_counts = Tournament.visible.where(circuit_id: ids).group(:circuit_id).count
    @league_counts = League.visible.where(circuit_id: ids).group(:circuit_id).count
  end

  def show
    @circuit = Circuit.preload(event_organizer: :user).find(params[:id])
    @standings = @circuit.standings.preload(player: :user).to_a
    @tournaments = circuit_events(@circuit.tournaments)
    @leagues = circuit_events(@circuit.leagues)
    @enrolled = enrolled_counts(@tournaments.to_a + @leagues.to_a)
  end

  private

  def circuit_events(scope) = ticket_preload(scope.visible.order(start_time: :desc)).to_a
end
