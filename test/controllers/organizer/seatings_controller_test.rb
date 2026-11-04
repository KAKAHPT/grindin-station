# frozen_string_literal: true

require "test_helper"

module Organizer
  class SeatingsControllerTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    end

    test "a manual swap labels both seatings manual and clears the fair-seating cost" do
      t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      round = t.rounds.create!(type: SwissRound, number: 1)
      pod1, pod2 = round.pods.order(:number).to_a
      from = pod1.seatings.first
      to = pod2.seatings.first
      assert_equal %w[fair fair], [from.assigned_by, to.assigned_by]
      players = [from.event_participant_id, to.event_participant_id]

      patch swap_organizer_tournament_round_seatings_path(t, round),
            params: { player: from.event_participant_id, pod: pod1.id, with_player: to.event_participant_id,
                      with_pod: pod2.id }

      assert_redirected_to organizer_tournament_round_path(t, round)
      from.reload
      to.reload
      assert_equal players.reverse, [from.event_participant_id, to.event_participant_id]
      assert_equal [%w[manual manual], [nil, nil]], [[from.assigned_by, to.assigned_by], [from.cost, to.cost]]
    end

    test "a swap with a seat that is not in the round goes back with a message, not a 500" do
      t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      round = t.rounds.create!(type: SwissRound, number: 1)
      pod1, pod2 = round.pods.order(:number).to_a
      from = pod1.seatings.first

      patch swap_organizer_tournament_round_seatings_path(t, round),
            params: { player: from.event_participant_id, pod: pod1.id, with_player: SecureRandom.uuid,
                      with_pod: pod2.id }

      assert_redirected_to organizer_tournament_round_path(t, round)
      assert_equal I18n.t("flash.alert.seating_not_found"), flash[:alert]
      assert_equal "fair", from.reload.assigned_by
    end
  end
end
