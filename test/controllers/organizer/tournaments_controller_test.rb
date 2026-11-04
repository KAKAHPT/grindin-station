# frozen_string_literal: true

require "test_helper"

module Organizer
  class TournamentsControllerTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    end

    test "the new form has no structure suggestion before anyone registers" do
      get new_organizer_tournament_path
      assert_response :success
      assert_not_includes response.body, "Suggested for"
    end

    test "an invalid tournament re-renders the form with 422 instead of redirecting" do
      assert_no_difference -> { Tournament.count } do
        post organizer_tournaments_path, params: {
          tournament: { name: "Inválido", start_time: 1.day.from_now, end_time: 2.days.from_now, round_minutes: 0 }
        }
      end
      assert_response :unprocessable_entity
      assert_select "form[action='#{organizer_tournaments_path}']"
    end

    test "a staff organizer can move the tournament to swiss, a judge cannot" do
      tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                           state: :registration_closed)
      co_organizer, judge =
        %w[organizer judge].map do |role|
          user = User.create!(name: role, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                              password: "password123")
          EventStaff.create!(event: tournament, user: user, role: role)
          user
        end

      sign_in(judge)
      patch organizer_tournament_path(tournament), params: { tournament: { state: "swiss" } }
      assert_redirected_to organizer_root_path
      assert tournament.reload.registration_closed?

      sign_in(co_organizer)
      get edit_organizer_tournament_path(tournament)
      assert_response :success
      patch organizer_tournament_path(tournament), params: { tournament: { state: "swiss" } }
      assert tournament.reload.swiss?
      assert_equal 1, tournament.rounds.count
    end

    private

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
