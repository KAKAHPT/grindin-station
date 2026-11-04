# frozen_string_literal: true

require "test_helper"

module Play
  class ReportsTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
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

    test "a 1v1 report page offers the best-of-three scores and the draws" do
      pod, seats = one_v_one_pod
      sign_in(seats[0])

      get play_pod_report_new_path(pod.event.slug, pod)

      assert_response :success
      assert_select "input[type=radio][name=games][value='2-0-0'][checked]"
      assert_select "input[type=radio][name=games][value='2-1-0']"
      assert_select "label[title^='1-0 on time']:has(input[type=radio][name=games][value='1-0-1'])", text: /1-0\s+time/
      assert_select "form:has(input[name=type][value=Draw]):has(input[name=games][value='1-1-1']) button", text: /1-1/
      assert_select "form:has(input[name=type][value=Draw]):has(input[name=games][value='0-0-1']) button", text: /0-0/
    end

    test "a best-of-one report page offers 1-0 and the 0-0 draw only" do
      pod, seats = one_v_one_pod(match_games: 1)
      sign_in(seats[0])

      get play_pod_report_new_path(pod.event.slug, pod)

      assert_select "input[type=radio][name=games]", 1
      assert_select "input[type=radio][name=games][value='1-0-0']"
      assert_select "input[name=games][value='1-1-1']", 0
      assert_select "input[name=games][value='0-0-1']"
    end

    test "a multiplayer report page has no score" do
      sign_in(@seats[0])
      get play_pod_report_new_path(@tournament.slug, @pod)

      assert_select "input[name=games]", 0
    end

    test "a 1v1 report stores the games in the pending result and the confirmation applies them" do
      pod, seats = one_v_one_pod
      pod.event.update!(result_confirmation: "one")
      sign_in(seats[0])

      post play_pod_report_path(pod.event.slug, pod), params: { type: "Win", winner_id: seats[1].id, games: "2-1-0" }

      assert_equal({ "type" => "Win", "winner_id" => seats[1].id, "games" => { "winner" => [2, 1, 0] } },
                   pod.reload.pending_result)
      sign_in(seats[1])
      post play_pod_confirm_path(pod.event.slug, pod)

      assert_equal :completed, pod.reload.report_status
      assert_equal [2, 1, 0], Result.current.find_by!(round: pod.round, event_participant: seats[1]).games
      assert_equal [1, 2, 0], Result.current.find_by!(round: pod.round, event_participant: seats[0]).games
    end

    test "a 1v1 draw with no confirmation is applied with its games" do
      pod, seats = one_v_one_pod
      pod.event.update!(result_confirmation: "none")
      sign_in(seats[0])

      post play_pod_report_path(pod.event.slug, pod), params: { type: "Draw", games: "1-1-1" }

      assert_equal :completed, pod.reload.report_status
      assert_equal [[1, 1, 1]], Result.current.where(round: pod.round).map(&:games).uniq
    end

    test "a 1v1 report with an impossible score or none is refused" do
      pod, seats = one_v_one_pod
      sign_in(seats[0])

      post play_pod_report_path(pod.event.slug, pod), params: { type: "Win", winner_id: seats[0].id, games: "2-2-0" }
      assert_equal I18n.t("results.not_allowed.impossible_score"), flash[:alert]
      post play_pod_report_path(pod.event.slug, pod), params: { type: "Win", winner_id: seats[0].id }
      assert_equal I18n.t("results.not_allowed.score_required"), flash[:alert]
      assert_nil pod.reload.pending_result
    end

    private

    # A published 1v1 swiss round's first pod and its players in seat order.
    def one_v_one_pod(match_games: 3)
      t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), format: "one_v_one",
                                  match_games: match_games)
      round = t.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true)
      pod = round.pods.order(:number).first
      [pod, pod.seatings.order(:order).map(&:event_participant)]
    end

    def sign_in(participant)
      user = participant.player.user
      user.update!(password: "password123")
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
