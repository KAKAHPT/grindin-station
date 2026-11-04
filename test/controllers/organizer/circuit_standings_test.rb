# frozen_string_literal: true

require "test_helper"

module Organizer
  # The organizer's circuit page lists the standings best first (rank, player, points, events).
  class CircuitStandingsTest < ActionDispatch::IntegrationTest
    test "the circuit page shows its standings, best first" do
      circuit = circuits(:standard_circuit)
      circuit.circuit_standings.create!(player: players(:player_one), points: 5, events_count: 1)
      circuit.circuit_standings.create!(player: players(:player_two), points: 12, events_count: 2)
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }

      get organizer_circuit_path(circuit)

      assert_response :success
      assert_select "p", text: "Organized by #{users(:organizer_user).name}"
      assert_select "tbody tr", 2
      assert_select "tbody tr:first-child td", text: players(:player_two).name
      assert_select "tbody tr:first-child td", text: "12"
    end
  end
end
