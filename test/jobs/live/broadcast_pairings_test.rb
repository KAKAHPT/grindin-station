# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

module Live
  class BroadcastPairingsTest < ActiveJob::TestCase
    include Turbo::Broadcastable::TestHelper # included on Action Cable load, which may not have happened yet

    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @pod = @round.pods.first
      clear_enqueued_jobs
    end

    test "a pod of a published round refreshes the pairings page in every locale" do
      @round.update!(published: true)

      %i[en pt].each do |locale|
        assert_turbo_stream_broadcasts(LiveBroadcasts.pairings_stream(@tournament.id, locale), count: 1) do
          BroadcastPodJob.perform_now(pod_id: @pod.id)
        end
      end
    end

    test "a round job refreshes the pairings page in every locale" do
      %i[en pt].each do |locale|
        assert_turbo_stream_broadcasts(LiveBroadcasts.pairings_stream(@tournament.id, locale), count: 1) do
          BroadcastRoundJob.perform_now(@round)
        end
      end
    end

    test "a pod of an unpublished round broadcasts nothing on the pairings stream" do
      %i[en pt].each do |locale|
        assert_no_turbo_stream_broadcasts(LiveBroadcasts.pairings_stream(@tournament.id, locale)) do
          BroadcastPodJob.perform_now(pod_id: @pod.id)
        end
      end
    end
  end
end
