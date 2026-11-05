# frozen_string_literal: true

require "test_helper"

module Rankings
  class RebuildJobTest < ActiveJob::TestCase
    setup do
      @organizer = event_organizers(:standard_organizer)
    end

    test "schedule! enqueues one rebuild in five minutes, however often it is called" do
      with_memory_cache do
        freeze_time do
          RebuildJob.schedule!
          RebuildJob.schedule!

          assert_enqueued_jobs 1, only: RebuildJob
          assert_enqueued_with(job: RebuildJob, at: 5.minutes.from_now)
        end
      end
    end

    test "perform clears the pending key, so the next change schedules again, and rebuilds" do
      with_memory_cache do
        RebuildJob.schedule!
        TournamentBuilder.build(players: 4, organizer: @organizer, state: :finished)

        RebuildJob.perform_now
        RebuildJob.schedule!

        assert_enqueued_jobs 2, only: RebuildJob
        assert_operator RankingContribution.count, :>=, 4
      end
    end

    test "FinishTournamentJob schedules a rebuild" do
      tournament = TournamentBuilder.build(players: 4, organizer: @organizer, state: :finished)

      assert_enqueued_with(job: RebuildJob) { Tournaments::FinishTournamentJob.perform_now(tournament) }
    end

    test "FinishLeagueJob schedules a rebuild" do
      assert_enqueued_with(job: RebuildJob) { Leagues::FinishLeagueJob.perform_now(leagues(:standard_league)) }
    end

    test "a result corrected on a closed round schedules a rebuild; one on an open round does not" do
      tournament = TournamentBuilder.build(players: 4, organizer: @organizer, state: :swiss)
      open = tournament.rounds.create!(type: SwissRound, number: 1).pods.sole

      assert_no_enqueued_jobs(only: RebuildJob) { Results::Apply.call(pod: open, type: "Draw", by: @organizer.user) }

      open.round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
      assert_enqueued_with(job: RebuildJob) { Results::Apply.call(pod: open, type: "Draw", by: @organizer.user) }
    end

    private

    # The test cache is a null store (every write succeeds); the debounce needs a real one.
    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end
  end
end
