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
      assert_equal Feeds.last_change(@t).to_i, feed[:updated]
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

    test "gives the format and the match length" do
      assert_equal ["multiplayer", 3], Feeds::Info.call(@t).values_at(:format, :matchGames)
      assert_equal ["one_v_one", 1],
                   Feeds::Info.call(build_1v1_feed_tournament(match_games: 1)).values_at(:format, :matchGames)
    end

    test "gives the pairing mode for multiplayer and none for 1v1" do
      assert_equal "swiss", Feeds::Info.call(@t)[:pairingMode]
      @t.update_column(:pairing_mode, "power") # rubocop:disable Rails/SkipsModelValidations
      assert_equal "power", Feeds::Info.call(@t)[:pairingMode]
      assert_nil Feeds::Info.call(build_1v1_feed_tournament)[:pairingMode]
    end
  end
end
