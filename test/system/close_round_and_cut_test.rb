# frozen_string_literal: true

require "application_system_test_case"

# Flow 3: the organizer marks every table, closes both swiss rounds, makes the Top 16, taps the winner of each
# cut table (they advance, the rest are eliminated) and calls time on the final.
class CloseRoundAndCutTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(swiss_rounds_count: 2, top_cut_size: 16) # rubocop:disable Rails/SkipsModelValidations
    @tournament.update!(top_cut_timeout_rule: "highest_seed_advances")
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: Time.current)
  end

  test "close round guard, round 2, cut winners advance, ranked final seats, time called advances the top seed" do # rubocop:disable Metrics/BlockLength
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_round_path(@tournament, @round)

    pods = @round.pods.order(:number).to_a
    pods.first(3).each { |pod| mark_winner(pod, seat: 1) }

    click_button "Close round"
    assert_text I18n.t("rounds.cannot_close", tables: pods.last.number)
    assert_nil @round.reload.finished_at

    within(pod_card(pods.last)) do
      click_button "Draw"
      click_button "Confirm"
    end
    assert_pod_completed(pods.last)

    click_button "Close round"
    assert_text I18n.t("rounds.next_round_created")
    assert_text "Round #2"
    round2 = @tournament.rounds.find_by!(number: 2)

    click_button "Publish"
    assert_text I18n.t("flash.notice.round_published")
    click_button "Start"
    assert_text I18n.t("flash.notice.round_started")
    round2.pods.order(:number).each { |pod| mark_winner(pod, seat: 2) }

    click_button "Close round"
    assert_text I18n.t("rounds.closed")
    click_button "Make cut"
    assert_text I18n.t("flash.notice.tournament_advanced")
    assert_predicate @tournament.reload, :single_elimination?

    cut = @tournament.rounds.find_by!(type: "SingleEliminationRound")
    click_button "Publish"
    assert_text I18n.t("flash.notice.round_published")
    click_button "Start"
    assert_text I18n.t("flash.notice.round_started")
    cut_pods = cut.pods.order(:number).to_a
    within(pod_card(cut_pods.first)) { assert_no_button "Draw" }
    advanced =
      cut_pods.map do |cut_pod|
        mark_winner(cut_pod, seat: 4)
        cut_pod.seatings.find_by!(order: 4).event_participant_id
      end
    assert_equal advanced.sort, Result.current.where(round: cut, type: "Advance").pluck(:event_participant_id).sort
    assert_equal 12, Result.current.where(round: cut, type: "Eliminated").count

    click_button "Close round"
    assert_text I18n.t("rounds.next_round_created")
    final = @tournament.rounds.where(type: "SingleEliminationRound").find_by!(number: cut.number + 1)
    pod = final.pods.sole
    assert_equal advanced.sort, pod.seatings.map(&:event_participant_id).sort
    seated = pod.seatings.order(:order).map(&:event_participant)
    assert_equal seated.sort_by { |p| -p.rank_score }.map(&:id), seated.map(&:id), "top-cut seats follow the standings"

    click_button "Publish"
    assert_text I18n.t("flash.notice.round_published")
    click_button "Start"
    assert_text I18n.t("flash.notice.round_started")

    within(pod_card(pod)) { accept_confirm(I18n.t("results.timeout_confirm")) { click_button "Time called" } }
    assert_text I18n.t("results.timeout_applied.highest_seed_advances")

    advances = Result.current.where(round: final, type: "Advance").where(event_participant_id: seated.map(&:id))
    assert_equal [seated.first.id], advances.pluck(:event_participant_id)
  end

  private

  def pod_card(pod)
    find("#pod_#{pod.id}")
  end

  # Taps the seat's row on the pod card, then presses Confirm.
  def mark_winner(pod, seat:)
    name = pod.seatings.find_by!(order: seat).event_participant.name
    within(pod_card(pod)) do
      find("li[role=button]") { |row| row["data-name"] == name }.click
      click_button "Confirm"
    end
    assert_text I18n.t("flash.notice.result_submitted")
    assert_pod_completed(pod)
  end

  def assert_pod_completed(pod)
    within(pod_card(pod)) { assert_text(/completed/i) }
  end
end
