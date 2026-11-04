# frozen_string_literal: true

require "test_helper"

module Play
  # A player acts only on their own table in the event's current round.
  class PodScopingTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @round.update!(published: true)
      @pod = @round.pods.order(:number).first
      @seats = @pod.event_participants.to_a
    end

    test "confirm and contest on a table the player is not seated at are not found" do
      @tournament.update!(result_confirmation: "one")
      other_pod = @round.pods.order(:number).second
      Results::Report.call(pod: other_pod, participant: other_pod.event_participants.first, type: "Draw")
      sign_in(@seats[0])

      post play_pod_confirm_path(@tournament.slug, other_pod)
      assert_response :not_found

      post play_pod_contest_path(@tournament.slug, other_pod), params: { reason: "No" }
      assert_response :not_found
      assert_not other_pod.reload.disputed?
      assert_equal 1, other_pod.confirmations.size
    end

    test "a table from an earlier round is not found" do
      @round.update_column(:finished_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      @tournament.rounds.create!(type: SwissRound, number: 2).update!(published: true)
      sign_in(@seats[0])

      post play_pod_report_path(@tournament.slug, @pod), params: { type: "Draw" }

      assert_response :not_found
      assert_equal :playing, @pod.reload.report_status
    end

    test "a player cannot act on a table they are not seated at" do
      other_pod = @round.pods.order(:number).second
      sign_in(@seats[0])

      post play_pod_report_path(@tournament.slug, other_pod), params: { type: "Draw" }

      assert_response :not_found
      assert_equal :playing, other_pod.reload.report_status
    end

    test "a player cannot act on a table of another event" do
      other = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      other_round = other.rounds.create!(type: SwissRound, number: 1)
      other_round.update!(published: true)
      other_pod = other_round.pods.first
      sign_in(@seats[0])

      post play_pod_report_path(@tournament.slug, other_pod), params: { type: "Draw" }

      assert_response :not_found
      assert_equal :playing, other_pod.reload.report_status
    end

    private

    def sign_in(participant)
      user = participant.player.user
      user.update!(password: "password123")
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
