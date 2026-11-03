# frozen_string_literal: true

require "test_helper"

module Organizer
  class TimeoutTest < ActionDispatch::IntegrationTest
    setup do
      @t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      @t.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      @t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@t, winners: (1..4).index_with(0))
      @round = @t.rounds.create!(type: SingleEliminationRound, number: 2)
      @pod = @round.pods.first
      @users =
        %w[judge scorekeeper].index_with do |role|
          user = User.create!(name: role, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                              password: "password123")
          EventStaff.create!(event: @t, user: user, role: role)
          user
        end
    end

    test "a judge can call time" do
      sign_in_as("judge")

      post timeout_organizer_tournament_round_pod_results_path(@t, @round, @pod)

      assert_redirected_to organizer_tournament_round_path(@t, @round)
      assert_equal I18n.t("results.timeout_applied.highest_seed_advances"), flash[:notice]
      assert_equal 1, Result.current.where(round: @round, type: "Advance").count
    end

    test "a scorekeeper is refused" do
      sign_in_as("scorekeeper")

      assert_no_difference -> { Result.count } do
        post timeout_organizer_tournament_round_pod_results_path(@t, @round, @pod)
      end
      assert_redirected_to organizer_root_path
    end

    test "a Swiss table redirects with an alert" do
      swiss = @t.rounds.find_by(number: 1)
      sign_in_as("judge")

      post timeout_organizer_tournament_round_pod_results_path(@t, swiss, swiss.pods.first)

      assert_redirected_to organizer_tournament_round_path(@t, swiss)
      assert_predicate flash[:alert], :present?
    end

    private

    def sign_in_as(role)
      post session_path,
           params: { session: { email_address: @users.fetch(role).email_address, password: "password123" } }
    end
  end
end
