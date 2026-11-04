# frozen_string_literal: true

require "test_helper"

module Play
  class ReportsTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @round.update!(published: true)
      @pod = @round.pods.order(:number).first
      @seats = @pod.event_participants.to_a
    end

    test "the report page offers a button per seat and a draw" do
      sign_in(@seats[0])
      get play_pod_report_new_path(@tournament.slug, @pod)

      assert_response :success
      @seats.each { |seat| assert_select "label", text: /#{seat.name}/ }
      assert_select "input[type=radio][value='#{@seats[0].id}'][checked]"
      assert_select "button", text: "Draw"
      assert_select "button", text: "Submit"
    end

    test "a top-cut report page offers no draw" do
      @tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => 0 })
      cut = @tournament.rounds.create!(type: SingleEliminationRound, number: 2)
      cut.update!(published: true)
      pod = cut.pods.sole
      sign_in(pod.event_participants.first)

      get play_pod_report_new_path(@tournament.slug, pod)

      assert_response :success
      assert_select "button", text: "Draw", count: 0
      assert_select "button", text: "Submit"
    end

    test "with no confirmation a report completes the table" do
      @tournament.update!(result_confirmation: "none")
      sign_in(@seats[0])

      post play_pod_report_path(@tournament.slug, @pod), params: { type: "Win", winner_id: @seats[2].id }

      assert_redirected_to play_me_path(@tournament.slug)
      assert_equal :completed, @pod.reload.report_status
      follow_redirect!
      assert_includes response.body, "Completed"
    end

    test "with one confirmation the reporter waits and another player confirms" do
      @tournament.update!(result_confirmation: "one")
      sign_in(@seats[0])
      post play_pod_report_path(@tournament.slug, @pod), params: { type: "Draw" }
      follow_redirect!
      assert_includes response.body, "Waiting for confirmation"
      assert_select "button", text: "Confirm", count: 0

      sign_in(@seats[3])
      get play_me_path(@tournament.slug)
      assert_select "button", text: "Confirm"
      post play_pod_confirm_path(@tournament.slug, @pod)

      assert_redirected_to play_me_path(@tournament.slug)
      assert_equal :completed, @pod.reload.report_status
    end

    test "contesting disputes the table and calls a judge" do
      @tournament.update!(result_confirmation: "one")
      sign_in(@seats[0])
      post play_pod_report_path(@tournament.slug, @pod), params: { type: "Win", winner_id: @seats[0].id }

      sign_in(@seats[1])
      assert_difference -> { JudgeCall.where(pod: @pod).count }, 1 do
        post play_pod_contest_path(@tournament.slug, @pod), params: { reason: "I won that game" }
      end

      assert_redirected_to play_me_path(@tournament.slug)
      assert_predicate @pod.reload, :disputed?
      follow_redirect!
      assert_includes response.body, "Judge called"
    end

    test "a refused action redirects with the reason" do
      @tournament.update!(self_report_enabled: false)
      sign_in(@seats[0])

      post play_pod_report_path(@tournament.slug, @pod), params: { type: "Draw" }

      assert_redirected_to play_me_path(@tournament.slug)
      assert_equal I18n.t("results.not_allowed.self_report_disabled"), flash[:alert]
    end

    private

    def sign_in(participant)
      user = participant.player.user
      user.update!(password: "password123")
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
