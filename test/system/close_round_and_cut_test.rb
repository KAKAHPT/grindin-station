# frozen_string_literal: true

require "application_system_test_case"

# Flow 3: the organizer marks every table, closes both swiss rounds, makes the cut and calls time on the final.
class CloseRoundAndCutTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(swiss_rounds_count: 2, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
    @tournament.update!(top_cut_timeout_rule: "highest_seed_advances")
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: Time.current)
  end

  test "close round guard, round 2, make cut with ranked seats, time called advances the highest seed" do # rubocop:disable Metrics/BlockLength
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_round_path(@tournament, @round)

    pods = @round.pods.order(:number).to_a
    pods.first(3).each { |pod| mark_winner(pod, seat: 1) }

    click_button "Close round"
    assert_text I18n.t("rounds.cannot_close", tables: pods.last.number)
    assert_nil @round.reload.finished_at

    within(pod_card(pods.last)) { click_button "Draw" }
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

    final = @tournament.rounds.find_by!(type: "SingleEliminationRound")
    pod = final.pods.sole
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

  # Taps the seat's row on the pod card, then confirms "<name> wins".
  def mark_winner(pod, seat:)
    name = pod.seatings.find_by!(order: seat).event_participant.name
    within(pod_card(pod)) do
      find("[role=button][data-name='#{name}']").click
      click_button "#{name} wins"
    end
    assert_text I18n.t("flash.notice.result_submitted")
    assert_pod_completed(pod)
  end

  def assert_pod_completed(pod)
    within(pod_card(pod)) { assert_text(/completed/i) }
  end
end
