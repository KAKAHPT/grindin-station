# frozen_string_literal: true

require "test_helper"

module Feeds
  class InfoTest < ActiveSupport::TestCase
    include FeedTournament

    setup { build_feed_tournament }

    test "describes the event and the running round" do
      feed = Feeds::Info.call(@t)

      assert_equal @t.slug, feed[:tid]
      assert_equal @t.name, feed[:name]
      assert_equal "swiss", feed[:state]
      assert_equal @t.start_time.utc.iso8601, feed[:starts_at]
      assert_equal @t.end_time.utc.iso8601, feed[:ends_at]
      assert_equal 16, feed[:players]
      assert_equal "2", feed[:round]
      assert_equal "2026-11-04T16:20:00Z", feed[:timerEnd]
    end

    test "no round and no timer before the first round is published" do
      fresh = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                      state: :registration_closed)
      feed = Feeds::Info.call(fresh)

      assert_nil feed[:round]
      assert_nil feed[:timerEnd]
      assert_equal "registration_closed", feed[:state]
    end

    test "a closed round has no timer" do
      @round2.update_columns(finished_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      assert_nil Feeds::Info.call(@t)[:timerEnd]
    end
  end
end
