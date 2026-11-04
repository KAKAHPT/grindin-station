# frozen_string_literal: true

require "test_helper"

module Results
  class ExpirePendingJobTest < ActiveJob::TestCase
    setup do
      @t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @t.update!(result_confirmation: "one", confirmation_timeout_minutes: 5)
      @old, @fresh = @t.rounds.create!(type: SwissRound, number: 1, started_at: 1.hour.ago).pods.order(:number).to_a
      @old_reporter = @old.event_participants.first
      @fresh_reporter = @fresh.event_participants.first
    end

    test "only pods pending past the timeout go to review" do
      travel_to(6.minutes.ago) { Report.call(pod: @old, participant: @old_reporter, type: "Draw") }
      travel_to(4.minutes.ago) { Report.call(pod: @fresh, participant: @fresh_reporter, type: "Draw") }

      ExpirePendingJob.perform_now

      assert_equal :review, @old.reload.report_status
      assert_not_nil @old.review_requested_at
      assert_equal :pending, @fresh.reload.report_status
      assert_empty @old.results
    end

    test "a pod already in review keeps its first request time" do
      travel_to(10.minutes.ago) { Report.call(pod: @old, participant: @old_reporter, type: "Draw") }
      ExpirePendingJob.perform_now
      first = @old.reload.review_requested_at

      travel 1.minute
      ExpirePendingJob.perform_now

      assert_equal first, @old.reload.review_requested_at
    end

    test "each event's own timeout applies" do
      patient = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      patient.update!(result_confirmation: "one", confirmation_timeout_minutes: 30)
      slow = patient.rounds.create!(type: SwissRound, number: 1, started_at: 1.hour.ago).pods.first
      travel_to(10.minutes.ago) do
        Report.call(pod: @old, participant: @old_reporter, type: "Draw")
        Report.call(pod: slow, participant: slow.event_participants.first, type: "Draw")
      end

      ExpirePendingJob.perform_now

      assert_equal :review, @old.reload.report_status
      assert_equal :pending, slow.reload.report_status
    end

    test "is scheduled every minute in production (development runs jobs inline, no recurring block)" do
      config = YAML.load_file(Rails.root.join("config/recurring.yml"))

      assert_equal({ "class" => "Results::ExpirePendingJob", "schedule" => "every minute" },
                   config.dig("production", "results_expire_pending"))
    end
  end
end
