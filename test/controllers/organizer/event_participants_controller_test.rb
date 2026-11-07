# frozen_string_literal: true

require "test_helper"

module Organizer
  class EventParticipantsControllerTest < ActionDispatch::IntegrationTest
    include RateLimitStore

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

    test "the search lists accounts by name with a masked e-mail, by e-mail in full, and flags those in the event" do
      inside = @tournament.event_participants.first.player.user
      outsider = User.create!(name: "Zed Outsider", email_address: "zed@example.org", password: "password123")

      get search_organizer_tournament_event_participants_path(@tournament, mode: "name", q: inside.name.first(6)),
          as: :json
      assert_response :success
      row = response.parsed_body.find { |r| r["player_id"] == inside.player.id }
      assert row["in_event"]
      assert_match(/\A.…@/, row["email"])

      get search_organizer_tournament_event_participants_path(@tournament, mode: "email", q: "zed@"), as: :json
      assert_equal([[outsider.player.id, "zed@example.org", false]],
                   response.parsed_body.map { |r| r.values_at("player_id", "email", "in_event") })

      get search_organizer_tournament_event_participants_path(@tournament, mode: "email", q: "ze"), as: :json
      assert_empty response.parsed_body
    end

    test "a player picked by name is added by player_id; the name tab without a pick re-renders with the error" do
      outsider = User.create!(name: "Zed Outsider", email_address: "zed@example.org", password: "password123")

      assert_difference -> { @tournament.event_participants.count }, 1 do
        post organizer_tournament_event_participants_path(@tournament),
             params: { mode: "name", event_participant: { player_id: outsider.player.id, accepted_terms: "1" } }
      end
      assert_equal outsider.player.id, @tournament.event_participants.order(:created_at).last.player_id

      assert_no_difference -> { @tournament.event_participants.count } do
        post organizer_tournament_event_participants_path(@tournament),
             params: { mode: "name", event_participant: { accepted_terms: "1" } }
      end
      assert_response :unprocessable_entity
      assert_match "Pick a player from the list", response.body
      assert_select "[data-add-tabs] [aria-selected=true]", text: "By name"
    end

    test "the search allows sixty lookups a minute per organizer" do
      with_memory_rate_limit_store do
        60.times do
          get search_organizer_tournament_event_participants_path(@tournament, mode: "name", q: "load"), as: :json
          assert_response :success
        end
        get search_organizer_tournament_event_participants_path(@tournament, mode: "name", q: "load"), as: :json
        assert_response :too_many_requests
      end
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
