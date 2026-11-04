# frozen_string_literal: true

require "test_helper"

module Play
  # A draft or canceled event has no public pages: only its staff can open them.
  class HiddenEventsTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      @tournament.rounds.create!(type: SwissRound, number: 1).update!(published: true)
    end

    test "draft and canceled events are not found for visitors but open for staff" do
      %i[draft canceled].each do |state|
        @tournament.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
        [play_event_path(@tournament.slug), play_pairings_path(@tournament.slug),
         play_standings_path(@tournament.slug), play_timer_path(@tournament.slug)].each do |path|
          get path
          assert_response :not_found, "#{state} #{path}"
        end
      end

      post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                              password: "password123" } }
      get play_pairings_path(@tournament.slug)
      assert_response :success
      get play_timer_path(@tournament.slug)
      assert_response :success
    end

    test "legacy public pages are not found for draft and canceled events except for staff" do
      round = @tournament.rounds.first
      pod = round.pods.first || round.pods.create!(number: 1)
      paths = [tournament_rounds_path(@tournament), tournament_round_path(@tournament, round),
               tournament_round_pods_path(@tournament, round), tournament_round_pod_path(@tournament, round, pod),
               tournament_event_participants_path(@tournament)]

      %i[draft canceled].each do |state|
        @tournament.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
        paths.each do |path|
          get path
          assert_response :not_found, "visitor #{state} #{path}"
        end
      end

      sign_in_user(users(:player_one))
      paths.each do |path|
        get path
        assert_response :not_found, "non-staff #{path}"
      end

      sign_in_user(users(:organizer_user))
      get paths[1]
      assert_response :success
    end

    test "legacy round and pod routes are read-only" do
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/tournaments/1/rounds/1/edit") }
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/tournaments/1/rounds/1/pods", method: :post)
      end
    end

    private

    def sign_in_user(user)
      user.update!(password: "password123")
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
