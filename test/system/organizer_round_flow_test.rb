# frozen_string_literal: true

require "application_system_test_case"

# Flow 1: the organizer takes a 16-player event from registration to a published first round.
class OrganizerRoundFlowTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer),
                                          state: :registration_open)
    @tournament.update_columns(swiss_rounds_count: 2, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
  end

  test "organizer closes registrations, starts the swiss and publishes round 1" do
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_path(@tournament)

    accept_confirm { click_button "Close Registrations" }
    assert_text I18n.t("flash.notice.tournament_updated")
    assert_predicate @tournament.reload, :registration_closed?

    accept_confirm { click_button "Move to Swiss stage" }
    assert_text I18n.t("flash.notice.tournament_updated")
    assert_predicate @tournament.reload, :swiss?

    click_link "Bracket"
    assert_text "Round #1"
    click_button "Publish"
    assert_text I18n.t("flash.notice.round_published")

    round = @tournament.rounds.find_by!(number: 1)
    assert_predicate round, :published?
    assert_equal 4, round.pods.count

    round.pods.preload(seatings: :event_participant).find_each do |pod|
      within "#pod_#{pod.id}" do
        assert_selector "h5", text: "Table #{pod.number}"
        pod.seatings.each do |seating|
          assert_selector "li", text: /\A#{seating.order}\s*#{Regexp.escape(seating.event_participant.name)}\b/
        end
      end
    end
    assert_button "Start"
  end

  test "a winner selection survives a live refresh" do
    round, pod, other = started_round_with_pods
    name = pod.seatings.order(:order).first.event_participant.name
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_round_path(@tournament, round)
    within("#pod_#{pod.id}") { find("li[role=button][data-name='#{name}']").click }
    assert_selector "#pod_#{pod.id} li[data-selected=true]"

    complete_and_refresh(round, other)

    within("#pod_#{pod.id}") do
      assert_selector "li[data-selected=true][data-name='#{name}']"
      assert_selector "[data-pod-result-target=confirmLabel]", text: "#{name} wins"
    end
  end

  test "a winner selection survives a live replace of its own pod" do
    round, = started_round_with_pods
    pod = round.pods.find_by!(number: 2)
    name = pod.seatings.order(:order).first.event_participant.name
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_round_path(@tournament, round)
    within("#pod_#{pod.id}") { find("li[role=button][data-name='#{name}']").click }
    assert_selector "#pod_#{pod.id} li[data-selected=true]"

    JudgeCall.create!(event: @tournament, pod: pod, reason: "Rules question")
    I18n.with_locale(:en) do
      Turbo::StreamsChannel.broadcast_replace_to(
        LiveBroadcasts.round_stream(round.id, :en),
        target: "pod_#{pod.id}_state", partial: "organizer/pods/state", locals: { pod: pod.reload }
      )
    end

    within("#pod_#{pod.id}") do
      assert_text(/judge called/i)
      assert_selector "li[data-selected=true][data-name='#{name}']"
      assert_selector "[data-pod-result-target=confirmLabel]", text: "#{name} wins"
    end
  end

  test "a pod completed meanwhile loses its winner picker on refresh" do
    round, pod, = started_round_with_pods
    name = pod.seatings.order(:order).first.event_participant.name
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_round_path(@tournament, round)
    within("#pod_#{pod.id}") { find("li[role=button][data-name='#{name}']").click }
    assert_selector "#pod_#{pod.id} li[data-selected=true]"

    complete_and_refresh(round, pod)

    within("#pod_#{pod.id}") do
      assert_no_selector "li[data-selected=true]"
      assert_no_selector "[data-pod-result-target=confirm]"
    end
    assert_no_selector "#pod_#{pod.id}[data-controller~='pod-result']"
    assert_no_text "#{name} wins"
  end

  private

  def started_round_with_pods
    @tournament.update!(result_confirmation: "none")
    round = @tournament.rounds.create!(type: SwissRound, number: 1)
    round.update!(published: true, started_at: Time.current)
    [round, *round.pods.order(:number).first(2)]
  end

  # Staff result on a pod, then a live refresh with no request id (so this page morphs).
  def complete_and_refresh(round, pod)
    winner = pod.seatings.order(:order).first.event_participant
    Results::Report.call(pod: pod, participant: winner, type: "Win", winner: winner)
    Turbo::StreamsChannel.broadcast_refresh_to(LiveBroadcasts.round_stream(round.id, :en))
    within("#pod_#{pod.id}") { assert_text(/completed/i) }
  end
end
