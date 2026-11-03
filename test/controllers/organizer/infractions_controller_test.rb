# frozen_string_literal: true

require "test_helper"

module Organizer
  class InfractionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      judge = User.create!(name: "Judge", email_address: "judge-#{SecureRandom.hex(3)}@example.com",
                           password: "password123")
      EventStaff.create!(event: @tournament, user: judge, role: "judge")
      post session_path, params: { session: { email_address: judge.email_address, password: "password123" } }
    end

    test "infractions only take players and pods of the event" do
      other = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      other_pod = other.rounds.create!(type: SwissRound, number: 1).pods.first
      player_id = @tournament.event_participants.first.player_id

      assert_no_difference -> { Infraction.count } do
        record(other.event_participants.first.player_id, nil)
        assert_response :not_found

        record(player_id, other_pod.id)
        assert_response :not_found
      end

      assert_difference -> { Infraction.count }, 1 do
        record(player_id, @round.pods.first.id)
      end
    end

    private

    def record(player_id, pod_id)
      post organizer_tournament_infractions_path(@tournament), params: {
        infraction: { player_id: player_id, pod_id: pod_id, kind: "game_play_errors", category: "missed_trigger",
                      penalty: "warning", description: "Missed a trigger" }
      }
    end
  end
end
