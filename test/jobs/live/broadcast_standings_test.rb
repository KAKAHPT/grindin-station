# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

module Live
  class BroadcastStandingsTest < ActiveJob::TestCase
    include Turbo::Broadcastable::TestHelper

    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1, published: true)
      @pod = @round.pods.first
      clear_enqueued_jobs
    end

    test "a round job refreshes the standings page in every locale" do
      I18n.available_locales.each do |locale|
        assert_turbo_stream_broadcasts(LiveBroadcasts.standings_stream(@tournament.id, locale), count: 1) do
          perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) { BroadcastRoundJob.perform_now(@round) }
        end
      end
    end

    test "a pod of an open round leaves the standings page alone" do
      I18n.available_locales.each do |locale|
        assert_no_turbo_stream_broadcasts(LiveBroadcasts.standings_stream(@tournament.id, locale)) do
          perform_enqueued_jobs { BroadcastPodJob.perform_now(pod_id: @pod.id) }
        end
      end
    end

    test "a pod of a closed round (a correction) refreshes the standings page" do
      @round.update!(finished_at: Time.current)
      clear_enqueued_jobs

      I18n.available_locales.each do |locale|
        assert_turbo_stream_broadcasts(LiveBroadcasts.standings_stream(@tournament.id, locale), count: 1) do
          perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) { BroadcastPodJob.perform_now(pod_id: @pod.id) }
        end
      end
    end
  end
end
