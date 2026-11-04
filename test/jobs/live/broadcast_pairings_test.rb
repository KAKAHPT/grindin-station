# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

module Live
  class BroadcastPairingsTest < ActiveJob::TestCase
    include Turbo::Broadcastable::TestHelper # included on Action Cable load, which may not have happened yet

    REFRESH = %(<turbo-stream action="refresh"></turbo-stream>)

    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @pod = @round.pods.first
      clear_enqueued_jobs
    end

    test "a pod of a published round refreshes the pairings page in every locale, through a debounced job" do
      @round.update!(published: true)

      I18n.available_locales.each do |locale|
        assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob,
                             args: [LiveBroadcasts.pairings_stream(@tournament.id, locale), { content: REFRESH }]) do
          BroadcastPodJob.perform_now(pod_id: @pod.id)
        end
        assert_turbo_stream_broadcasts(LiveBroadcasts.pairings_stream(@tournament.id, locale), count: 1) do
          perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob)
        end
      end
    end

    test "a round job refreshes the pairings page in every locale" do
      I18n.available_locales.each do |locale|
        assert_turbo_stream_broadcasts(LiveBroadcasts.pairings_stream(@tournament.id, locale), count: 1) do
          perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) { BroadcastRoundJob.perform_now(@round) }
        end
      end
    end

    test "a judge call on a pod does not refresh the pairings page" do
      @round.update!(published: true)

      I18n.available_locales.each do |locale|
        call = nil
        assert_no_turbo_stream_broadcasts(LiveBroadcasts.pairings_stream(@tournament.id, locale)) do
          perform_enqueued_jobs do
            call = JudgeCall.create!(event: @tournament, pod: @pod, reason: "Rules question")
          end
        end
        call.destroy! # a pod has one open call at most
      end
    end

    test "a pod of an unpublished round broadcasts nothing on the pairings stream" do
      I18n.available_locales.each do |locale|
        assert_no_turbo_stream_broadcasts(LiveBroadcasts.pairings_stream(@tournament.id, locale)) do
          perform_enqueued_jobs { BroadcastPodJob.perform_now(pod_id: @pod.id) }
        end
      end
    end
  end
end
