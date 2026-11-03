# frozen_string_literal: true

require "test_helper"

module Play
  class JudgeCallsTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @round.update!(published: true)
      @pod = @round.pods.order(:number).first
      @seats = @pod.event_participants.to_a
    end

    test "calling a judge opens a call for the player's table" do
      sign_in(@seats[2])

      assert_difference -> { JudgeCall.count }, 1 do
        post play_judge_calls_path(@tournament.slug)
      end

      call = JudgeCall.order(:created_at).last
      assert_equal @pod, call.pod
      assert_equal @seats[2], call.participant
      assert_equal @tournament.id, call.event_id
      assert_redirected_to play_me_path(@tournament.slug)
      follow_redirect!
      assert_includes response.body, "Judge called"
    end

    test "a second judge call for the same table creates nothing" do
      sign_in(@seats[2])
      post play_judge_calls_path(@tournament.slug)

      assert_no_difference -> { JudgeCall.count } do
        post play_judge_calls_path(@tournament.slug)
      end
      assert_redirected_to play_me_path(@tournament.slug)
    end

    test "without a table a second judge call creates nothing and the waiting page shows it" do
      @round.update!(published: false)
      sign_in(@seats[2])
      post play_judge_calls_path(@tournament.slug)
      assert_nil JudgeCall.order(:created_at).last.pod

      assert_no_difference -> { JudgeCall.count } do
        post play_judge_calls_path(@tournament.slug)
      end
      follow_redirect!
      assert_includes response.body, "Waiting for pairings"
      assert_includes response.body, "Judge called"
      assert_select "button", text: "Call a judge", count: 0
    end

    private

    def sign_in(participant)
      user = participant.player.user
      user.update!(password: "password123")
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
