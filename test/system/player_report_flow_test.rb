# frozen_string_literal: true

require "application_system_test_case"

# Flow 2: a player reports from their phone, a tablemate contests, the Judge Center gets the call.
class PlayerReportFlowTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    @tournament.update!(result_confirmation: "none", self_report_enabled: true)
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: Time.current)
    @pod = @round.pods.find_by!(number: 1)
    @reporter, @contester = @pod.seatings.order(:order).first(2)
  end

  test "a player reports a win, a tablemate contests it and the Judge Center shows the call" do # rubocop:disable Metrics/BlockLength
    player_session(@reporter) do
      visit play_me_path(@tournament.slug)
      assert_selector "[data-table-number]", text: @pod.number.to_s
      assert_selector "[data-seat-number]", text: @reporter.order.to_s

      click_link "Report result"
      assert_checked_field @reporter.event_participant.name
      click_button "Submit"

      assert_text I18n.t("play.notices.reported")
      assert_selector "[data-report-status]", text: /completed/i
    end
    assert_equal :completed, @pod.reload.report_status
    assert_equal "Win", Result.current.find_by(round: @round, event_participant_id: @reporter.event_participant_id).type

    player_session(@contester) do
      visit play_me_path(@tournament.slug)
      assert_selector "[data-seat-number]", text: @contester.order.to_s
      fill_in "Why do you contest the result?", with: "I won that game"
      click_button "Contest"

      assert_text I18n.t("play.notices.contested")
      assert_selector "[data-report-status]", text: /disputed/i
    end
    assert_predicate @pod.reload, :disputed?

    sign_in_as(users(:organizer_user))
    visit organizer_tournament_judge_calls_path(@tournament)
    call = JudgeCall.find_by!(pod: @pod)
    within "##{ActionView::RecordIdentifier.dom_id(call)}" do
      assert_text @contester.event_participant.name
      assert_text "Result contested: I won that game"
      click_button "Acknowledge"
    end
    assert_text I18n.t("flash.notice.judge_call_acknowledged")
    assert_equal "acknowledged", call.reload.status
  end

  private

  def player_session(seating)
    user = seating.event_participant.player.user
    user.update!(password: "password123")
    Capybara.using_session("player-#{seating.id}") do
      use_phone_viewport
      sign_in_as(user)
      yield
    end
  end
end
