# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# Live updates: what reaches "my table" (one stream per participant and locale) and the organizer
# round page (one stream per round and locale) when the round, a pod, a result or a judge call changes.
class PodBroadcastTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper # included on Action Cable load, which may not have happened yet

  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.update!(self_report_enabled: true)
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @pod = @round.pods.order(:number).first
    @seated = @pod.seatings.order(:order).map(&:event_participant)
    @bye = @round.pods.order(:number).second.seatings.order(:order).last.tap(&:delete).event_participant
  end

  test "publishing the round pushes every participant their table, or their bye" do
    perform_enqueued_jobs { @round.update!(published: true) }

    table = capture_turbo_stream_broadcasts(table_stream(@seated.second)).sole
    assert_equal "replace", table["action"]
    assert_equal "my_table", table["target"]
    assert_includes table.to_html, "data-table-number"
    assert_match(/data-seat-number[^>]*>2</, table.to_html)
    assert_match(/data-me[^>]*>.*#{@seated.second.name}/m, table.to_html)

    assert_includes capture_turbo_stream_broadcasts(table_stream(@bye)).sole.to_html, I18n.t("play.tables.bye")
    assert_turbo_stream_broadcasts LiveBroadcasts.round_stream(@round.id, :en), count: 1 # the refresh
  end

  test "each locale gets its own copy" do
    perform_enqueued_jobs { @round.update!(published: true) }

    pt = capture_turbo_stream_broadcasts(table_stream(@seated.first, :pt)).sole.to_html
    assert_includes pt, I18n.t("play.call_judge", locale: :pt)
    assert_includes pt, "locale=pt"
    assert_not_includes capture_turbo_stream_broadcasts(table_stream(@seated.first)).sole.to_html, "locale="
  end

  test "a staff result updates the pod card's state, refreshes the round page and every seat's table" do
    @round.update!(published: true, started_at: Time.current)

    perform_enqueued_jobs do
      Results::Apply.call(pod: @pod, type: "Win", winner: @seated.first, by: users(:organizer_user))
    end

    round_broadcasts = capture_turbo_stream_broadcasts(LiveBroadcasts.round_stream(@round.id, :en))
    state = round_broadcasts.find { |b| b["action"] == "replace" }
    assert_equal "pod_#{@pod.id}_state", state["target"]
    assert_includes state.to_html, "Completed"
    assert(round_broadcasts.any? { |b| b["action"] == "refresh" })
    assert_not_includes state.to_html, I18n.t("rounds.add_extra_time"), "staff buttons stay out of the stream"

    @seated.each do |participant|
      assert_includes capture_turbo_stream_broadcasts(table_stream(participant)).last.to_html, "data-report-status"
    end
    assert_match(/Completed/i, capture_turbo_stream_broadcasts(table_stream(@seated.last)).last.to_html)
  end

  test "a player's pending report reaches the tablemates, who can now confirm" do
    @tournament.update!(result_confirmation: "all")
    @round.update!(published: true, started_at: Time.current)

    perform_enqueued_jobs do
      Results::Report.call(pod: @pod, participant: @seated.first, type: "Win", winner: @seated.first)
    end

    tablemate = capture_turbo_stream_broadcasts(table_stream(@seated.second)).last.to_html
    assert_includes tablemate, I18n.t("play.confirm")
    assert_not_includes capture_turbo_stream_broadcasts(table_stream(@seated.first)).last.to_html,
                        I18n.t("play.confirm")
  end

  test "acknowledging a judge call updates the table; a call without a pod reaches the player alone" do
    @round.update!(published: true)
    call = JudgeCalls::Open.call(event: @tournament, pod: @pod, participant: @seated.first, reason: "Help")

    perform_enqueued_jobs { call.acknowledge!(by: users(:organizer_user)) }
    assert_includes capture_turbo_stream_broadcasts(table_stream(@seated.third)).last.to_html, "data-judge-called"

    perform_enqueued_jobs do
      JudgeCalls::Open.call(event: @tournament, pod: nil, participant: @bye, reason: "Help")
    end
    assert_includes capture_turbo_stream_broadcasts(table_stream(@bye)).last.to_html, "data-judge-called"
  end

  test "nothing goes out for an unpublished round" do
    perform_enqueued_jobs { @pod.update!(extra_time: 5) }

    assert_no_turbo_stream_broadcasts table_stream(@seated.first)
    assert_no_turbo_stream_broadcasts LiveBroadcasts.round_stream(@round.id, :en)
  end

  test "correcting an older round updates its card but leaves the tables on the current round" do
    @round.update!(published: true, started_at: Time.current)
    @round.update_columns(finished_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    @tournament.rounds.create!(type: SwissRound, number: 2).update!(published: true)
    clear_enqueued_jobs

    perform_enqueued_jobs { Results::Apply.call(pod: @pod, type: "Draw", by: users(:organizer_user)) }

    assert_turbo_stream_broadcasts LiveBroadcasts.round_stream(@round.id, :en)
    assert_no_turbo_stream_broadcasts table_stream(@seated.first)
  end

  test "undoing a round pushes every participant the reopened round's table" do
    @round.update!(published: true, started_at: Time.current)
    @round.update_columns(finished_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    @tournament.rounds.create!(type: SwissRound, number: 2).update!(published: true)
    clear_enqueued_jobs

    perform_enqueued_jobs do
      Round.transaction do
        @tournament.rounds.find_by!(number: 2).destroy!
        @round.reload.update!(finished_at: nil)
      end
    end

    @round.event_participants.each do |participant|
      assert_turbo_stream_broadcasts table_stream(participant), count: 1
    end
    assert_match(/data-seat-number[^>]*>2</, capture_turbo_stream_broadcasts(table_stream(@seated.second)).sole.to_html)
  end

  private

  def table_stream(participant, locale = :en)
    LiveBroadcasts.table_stream(@tournament, participant, locale)
  end
end
