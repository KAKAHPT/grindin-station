# frozen_string_literal: true

require "test_helper"

module Organizer
  class ResultCorrectionTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
      @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      @round = @t.rounds.create!(type: SwissRound, number: 1)
      @pod = @round.pods.first
      @winner = @pod.seatings.last.event_participant
      TournamentBuilder.play_round!(@t, winners: { 1 => 0 })
      @t.rounds.create!(type: SwissRound, number: 2).publish!
    end

    test "correcting a closed round with a later round published needs confirmation" do
      assert_no_difference -> { Result.count } do
        post organizer_tournament_round_pod_results_path(@t, @round, @pod),
             params: { result: { type: "Win", event_participant_id: @winner.id } }
      end

      assert_nil flash[:alert]
      assert_response :unprocessable_content
      assert_includes response.body, I18n.t("results.later_round_warning")
      assert_select "input[type=checkbox][name=confirm]"
    end

    test "with confirm=1 the correction is applied and recorded by the current user" do
      post organizer_tournament_round_pod_results_path(@t, @round, @pod),
           params: { result: { type: "Win", event_participant_id: @winner.id }, confirm: "1" }

      assert_redirected_to organizer_tournament_round_path(@t, @round)
      current = Result.current.find_by(round: @round, event_participant: @winner)
      assert_instance_of Win, current
      assert_equal users(:organizer_user).id, current.recorded_by_user_id
      assert_equal 8, Result.where(round: @round).count
    end
  end
end
