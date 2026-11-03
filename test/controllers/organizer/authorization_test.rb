# frozen_string_literal: true

require "test_helper"

module Organizer
  class AuthorizationTest < ActionDispatch::IntegrationTest
    ROLES = %w[organizer judge scorekeeper].freeze

    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @participant = @tournament.event_participants.first
      @users = { "organizer" => users(:organizer_user) }
      %w[judge scorekeeper].each do |role|
        user = User.create!(name: role.capitalize, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
        EventStaff.create!(event: @tournament, user: user, role: role)
        @users[role] = user
      end
    end

    test "the rounds page is open to the organizer and the judge only" do
      expected = { "organizer" => 200, "judge" => 200, "scorekeeper" => 302 }
      assert_matrix(expected) { get organizer_tournament_round_path(@tournament, @round) }
    end

    test "editing the tournament is for the organizer only" do
      expected = { "organizer" => 200, "judge" => 302, "scorekeeper" => 302 }
      assert_matrix(expected) { get edit_organizer_tournament_path(@tournament) }
    end

    test "check-in is open to the organizer and the scorekeeper, not the judge" do
      ROLES.each do |role|
        @participant.update!(checked_in: false)
        sign_in_as(role)
        patch organizer_tournament_event_participant_path(@participant.event, @participant),
              params: { event_participant: { checked_in: true } }

        assert_equal role != "judge", @participant.reload.checked_in?, role
        assert_redirected_to organizer_root_path if role == "judge"
      end
    end

    test "a scorekeeper can only change check-in and paid" do
      sign_in_as("scorekeeper")
      patch organizer_tournament_event_participant_path(@tournament, @participant),
            params: { event_participant: { paid: true, dropped: true } }

      @participant.reload
      assert @participant.paid?
      assert_not @participant.dropped?
    end

    test "the staff page is for the owner only" do
      expected = { "organizer" => 200, "judge" => 302, "scorekeeper" => 302 }
      assert_matrix(expected) { get organizer_tournament_staff_index_path(@tournament) }
    end

    test "a user with no role on the event is turned away" do
      sign_in_as_user(users(:player_one))
      get organizer_tournament_round_path(@tournament, @round)
      assert_response :redirect

      get organizer_root_path
      assert_redirected_to root_url
    end

    test "staff see the events they work on in the organizer index" do
      sign_in_as("judge")
      get organizer_root_path
      assert_response :success
      assert_includes response.body, @tournament.name

      get organizer_tournament_path(@tournament)
      assert_response :success
    end

    test "every role can open result entry" do
      pod = @round.pods.first
      expected = { "organizer" => 200, "judge" => 200, "scorekeeper" => 200 }
      assert_matrix(expected) { get new_organizer_tournament_round_pod_result_path(@tournament, @round, pod) }
    end

    private

    def assert_matrix(expected)
      actual =
        ROLES.index_with do |role|
          sign_in_as(role)
          yield
          response.status
        end
      assert_equal expected, actual
    end

    def sign_in_as(role)
      sign_in_as_user(@users.fetch(role))
    end

    def sign_in_as_user(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
