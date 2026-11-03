# frozen_string_literal: true

require "test_helper"

module Organizer
  class TopCutResultTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
      @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      @t.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      @t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@t, winners: { 1 => 0 })
      @t.update_column(:state, :single_elimination) # rubocop:disable Rails/SkipsModelValidations
      @round = @t.rounds.create!(type: SingleEliminationRound, number: 2)
      @round.update!(published: true, started_at: Time.current)
      @pod = @round.pods.first
    end

    test "a draw in the top cut is refused with 422" do
      assert_no_difference -> { Result.current.where(round: @round).count } do
        post organizer_tournament_round_pod_results_path(@t, @round, @pod), params: { result: { type: "Draw" } }
      end

      assert_response :unprocessable_content
      assert_equal I18n.t("results.not_allowed.draw_in_top_cut"), flash[:alert]
    end

    test "a win in the top cut is stored as Advance" do
      winner = @pod.seatings.max_by(&:order).event_participant

      post organizer_tournament_round_pod_results_path(@t, @round, @pod),
           params: { result: { type: "Win", event_participant_id: winner.id } }

      assert_redirected_to organizer_tournament_round_path(@t, @round)
      assert_equal "Advance", Result.current.find_by(round: @round, event_participant: winner).type
      assert_equal 3, Result.current.where(round: @round, type: "Eliminated").count
    end

    test "the cut pod card offers no Draw button" do
      get organizer_tournament_round_path(@t, @round)

      assert_response :success
      assert_select "#pod_#{@pod.id} input[name='result[type]'][value=Draw]", count: 0
      assert_select "#pod_#{@pod.id} input[name='result[type]'][value=Win]", count: 4
    end
  end
end
