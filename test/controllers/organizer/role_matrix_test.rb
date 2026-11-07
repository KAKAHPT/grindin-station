# frozen_string_literal: true

require "test_helper"

module Organizer
  # What each staff role is refused (and the one write a scorekeeper must have).
  class RoleMatrixTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @pod = @round.pods.order(:number).first
      @participant = @pod.seatings.first.event_participant
      @users =
        %w[organizer judge scorekeeper caster].index_with do |role|
          user = User.create!(name: role, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                              password: "password123")
          EventStaff.create!(event: @tournament, user: user, role: role)
          user
        end
    end

    test "a scorekeeper is refused on infractions" do
      infraction = Infraction.create!(event: @tournament, player: @participant.player, description: "x")
      sign_in_as("scorekeeper")

      assert_no_difference -> { Infraction.count } do
        get organizer_tournament_event_participant_infractions_path(@tournament, @participant)
        assert_refused
        get new_organizer_tournament_infraction_path(@tournament, player_id: @participant.player_id)
        assert_refused
        post organizer_tournament_infractions_path(@tournament),
             params: { infraction: { player_id: @participant.player_id, description: "x" } }
        assert_refused
        delete organizer_tournament_event_participant_infraction_path(@tournament, @participant, infraction)
        assert_refused
      end
    end

    test "judges and scorekeepers cannot swap seats or roll back a round" do
      other = @round.pods.order(:number).second.seatings.first
      %w[judge scorekeeper].each do |role|
        sign_in_as(role)
        patch swap_organizer_tournament_round_seatings_path(@tournament, @round),
              params: { player: @participant.id, pod: @pod.id, with_player: other.event_participant_id,
                        with_pod: other.pod_id }
        assert_refused
        delete organizer_tournament_round_path(@tournament, @round)
        assert_refused
      end
      assert @tournament.rounds.exists?(@round.id)
      assert_equal @participant.id, @pod.seatings.first.reload.event_participant_id
    end

    test "a judge cannot add players" do
      sign_in_as("judge")
      get new_organizer_tournament_event_participant_path(@tournament)
      assert_refused
      assert_no_difference -> { EventParticipant.count } do
        post organizer_tournament_event_participants_path(@tournament),
             params: { event_participant: { player_name: "New", player_email: "new@example.com" } }
      end
      assert_refused
    end

    test "only the owner adds or removes staff" do
      staff = @tournament.event_staff.find_by(role: "scorekeeper")
      %w[organizer judge].each do |role|
        sign_in_as(role)
        assert_no_difference -> { EventStaff.count } do
          post organizer_tournament_staff_index_path(@tournament),
               params: { event_staff: { email_address: users(:player_one).email_address, role: "judge" } }
          assert_refused
          delete organizer_tournament_staff_path(@tournament, staff)
          assert_refused
        end
      end
    end

    test "a scorekeeper records a result" do
      sign_in_as("scorekeeper")
      assert_difference -> { Result.count }, @pod.seatings.count do
        post organizer_tournament_round_pod_results_path(@tournament, @round, @pod),
             params: { result: { type: "Win", event_participant_id: @participant.id } }
      end
      assert_redirected_to organizer_tournament_round_path(@tournament, @round)
    end

    test "a caster reads the overview, the roster and the rounds, and nothing else" do
      sign_in_as("caster")
      get organizer_tournament_path(@tournament)
      assert_response :success
      get organizer_tournament_event_participants_path(@tournament, layout: "application")
      assert_response :success
      assert_select "a", text: "Add player", count: 0
      assert_select "[data-tip]", count: 0
      get organizer_tournament_round_path(@tournament, @round)
      assert_response :success
      assert_select "form button", text: /Start|Close|Publish/, count: 0

      get organizer_tournament_judge_calls_path(@tournament)
      assert_refused
      get edit_organizer_tournament_path(@tournament)
      assert_refused
      assert_no_difference -> { Result.count + EventParticipant.count } do
        post organizer_tournament_round_pod_results_path(@tournament, @round, @pod),
             params: { result: { type: "Win", event_participant_id: @participant.id } }
        assert_refused
        patch check_in_organizer_tournament_event_participant_path(@tournament, @participant)
        assert_refused
        post organizer_tournament_event_participants_path(@tournament),
             params: { event_participant: { player_name: "New", accepted_terms: "1" } }
        assert_refused
      end
    end

    private

    def assert_refused
      assert_redirected_to organizer_root_path
      assert_equal I18n.t("flash.alert.not_allowed"), flash[:alert]
    end

    def sign_in_as(role)
      post session_path,
           params: { session: { email_address: @users.fetch(role).email_address, password: "password123" } }
    end
  end
end
