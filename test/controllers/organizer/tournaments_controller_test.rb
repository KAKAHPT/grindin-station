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

    test "the new form offers the format, and the match length for 1v1 behind the format-fields toggle" do
      get new_organizer_tournament_path

      assert_select "form[data-controller~=format-fields]" do
        assert_select "select[name='tournament[format]']:not([disabled])" do
          assert_select "option[value=multiplayer][selected]", text: "Multiplayer pods"
          assert_select "option[value=one_v_one]", text: "1v1"
        end
        assert_select "[data-format-fields-target=matchGames][hidden] select[name='tournament[match_games]']" do
          assert_select "option[value='3']", text: "Best of 3"
          assert_select "option[value='1']", text: "Best of 1"
        end
        assert_select "input[name='tournament[points_win]'][data-format-fields-target=points][value='7']"
      end
    end

    test "a 1v1 best-of-one tournament is created from the form" do
      assert_difference -> { Tournament.count } do
        post organizer_tournaments_path, params: {
          tournament: { name: "Duelos", start_time: 1.day.from_now, end_time: 2.days.from_now,
                        format: "one_v_one", match_games: "1",
                        points_win: 3, points_draw: 1, points_loss: 0, points_bye: 3 }
        }
      end

      tournament = Tournament.find_by!(name: "Duelos")
      assert_equal ["one_v_one", 1, 3], [tournament.format, tournament.match_games, tournament.points_win]
    end

    test "the edit form shows the format locked and keeps the match length visible for 1v1" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open, format: "one_v_one")

      get edit_organizer_tournament_path(tournament)

      assert_response :success
      assert_select "select[name='tournament[format]'][disabled] option[value=one_v_one][selected]"
      assert_select "[data-format-fields-target=matchGames]:not([hidden]) select[name='tournament[match_games]']"
    end

    test "a tampered update cannot switch the format" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open)

      patch organizer_tournament_path(tournament), params: { tournament: { format: "one_v_one", name: "Renomeado" } }

      assert_redirected_to organizer_tournament_path(tournament)
      assert_equal ["multiplayer", "Renomeado"], tournament.reload.values_at(:format, :name)
    end

    test "a mid-swiss update cannot switch the match length" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           format: "one_v_one")

      patch organizer_tournament_path(tournament), params: { tournament: { match_games: "1" } }

      assert_response :unprocessable_entity
      assert_equal 3, tournament.reload.match_games
    end

    private

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
