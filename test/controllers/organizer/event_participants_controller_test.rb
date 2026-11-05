# frozen_string_literal: true

require "test_helper"

module Organizer
  class EventParticipantsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                            state: :registration_open)
      post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                              password: "password123" } }
    end

    test "adding an e-mail already in the event re-renders with the error" do
      email = @tournament.event_participants.first.player.user.email_address

      assert_no_difference -> { @tournament.event_participants.count } do
        post organizer_tournament_event_participants_path(@tournament),
             params: { event_participant: { player_email: email, player_name: "Dup", accepted_terms: "1" } }
      end

      assert_response :unprocessable_entity
      assert_match "is already in this event", response.body
    end

    test "a guest added with no name and no e-mail is called Manual player 1" do
      post organizer_tournament_event_participants_path(@tournament),
           params: { event_participant: { accepted_terms: "1" } }

      assert_response :redirect
      assert_equal "Manual player 1", @tournament.event_participants.order(:created_at).last.name
    end

    test "a second guest with the same name re-renders with the error" do
      2.times do
        post organizer_tournament_event_participants_path(@tournament),
             params: { event_participant: { player_name: "Ana Costa", accepted_terms: "1" } }
      end

      assert_response :unprocessable_entity
      assert_match "name already used in this event", response.body
    end
  end
end
