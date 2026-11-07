# frozen_string_literal: true

require "test_helper"

module Feeds
  class RoundsTest < ActiveSupport::TestCase
    include FeedTournament

    setup { build_feed_tournament }

    test "lists the published rounds with their tables, winners and statuses" do
      feed = Feeds::Rounds.call(@t)

      assert_equal @t.slug, feed[:tid]
      assert_equal "2", feed[:latest]
      assert_equal 80, feed[:roundTime]
      assert_equal %w[1 2], feed[:rounds].pluck(:round)

      one, two = feed[:rounds].pluck(:tables)
      assert_equal [1, 2, 3, 4], one.pluck(:table)
      assert_equal ["Completed"] * 4, one.pluck(:status)
      assert_equal [seated(@round1, 1)[0].name, seated(@round1, 2)[1].name, "Draw", seated(@round1, 4)[3].name],
                   one.pluck(:winner)
      assert_equal [false, false, true, false], one.pluck(:draw)

      assert_equal %w[Completed Active Active Active], two.pluck(:status)
      assert_equal [seated(@round2, 1)[0].name, "", "", ""], two.pluck(:winner)
    end

    test "matches the relay's clock keys: updated, start, clock and end in epoch seconds, ended per table" do
      @round1.update_columns(finished_at: ROUND_TWO_STARTED_AT - 10.minutes) # rubocop:disable Rails/SkipsModelValidations
      feed = Feeds::Rounds.call(@t)
      one, two = feed[:rounds]

      assert_equal Feeds.last_change(@t).to_i, feed[:updated]
      assert_equal [(ROUND_TWO_STARTED_AT - 2.hours).to_i, 80 * 60, (ROUND_TWO_STARTED_AT - 10.minutes).to_i],
                   one.values_at(:start, :clock, :end)
      assert_equal [ROUND_TWO_STARTED_AT.to_i, 80 * 60, nil], two.values_at(:start, :clock, :end)

      reported = Result.where(round: @round2, event_participant: seated(@round2, 1)).maximum(:created_at)
      assert_equal [reported.to_i, nil, nil, nil], two[:tables].pluck(:ended)
      assert(one[:tables].all? { |table| table[:ended].is_a?(Integer) })
    end

    test "a round that has not started has no start and no end" do
      @round2.update_columns(started_at: nil) # rubocop:disable Rails/SkipsModelValidations
      assert_equal [nil, 80 * 60, nil], Feeds::Rounds.call(@t)[:rounds].last.values_at(:start, :clock, :end)
    end

    test "no seeds while the organizer hides the standings until the end" do
      @t.update_columns(hide_standings_until_finished: true) # rubocop:disable Rails/SkipsModelValidations
      feed = Feeds::Rounds.call(@t.reload)

      assert(feed[:rounds].flat_map { |r| r[:tables] }.flat_map { |t| t[:players] }.all? { |p| p[:seed].nil? })
    end

    test "players sit in seat order with their current rank as seed, each once per round" do
      feed = Feeds::Rounds.call(@t)
      ranks = Feeds::Standings.call(@t)[:standings].to_h { |row| [row[:name], row[:rank]] }

      feed[:rounds].each do |round|
        names = round[:tables].flat_map { |table| table[:players].pluck(:name) }
        assert_equal 16, names.size
        assert_equal names.uniq, names
      end
      table = feed[:rounds].first[:tables].first
      assert_equal seated(@round1, 1).map(&:name), table[:players].pluck(:name)
      assert_equal(table[:players].map { |p| ranks.fetch(p[:name]) }, table[:players].pluck(:seed))
      assert_equal [""] * 4, table[:players].pluck(:commander)
    end

    test "a round that has not started shows its tables as pending and no timer" do
      @round2.update_columns(started_at: nil) # rubocop:disable Rails/SkipsModelValidations
      Result.where(round: @round2).delete_all
      @round2.pods.update_all(pending_result: nil) # rubocop:disable Rails/SkipsModelValidations

      assert_equal ["Pending"] * 4, Feeds::Rounds.call(@t)[:rounds].last[:tables].pluck(:status)
      assert_nil Feeds::Info.call(@t)[:timerEnd]
    end

    test "unpublished rounds are left out" do
      @round2.update_columns(published: false) # rubocop:disable Rails/SkipsModelValidations
      feed = Feeds::Rounds.call(@t)

      assert_equal %w[1], feed[:rounds].pluck(:round)
      assert_equal "1", feed[:latest]
    end

    test "a top cut round is named after the players in it and has no timer when it is the final" do
      TournamentBuilder.play_round!(@t, winners: { 2 => 0, 3 => 0, 4 => 0 }) # pod 1 is reported
      cut = @t.rounds.create!(type: SingleEliminationRound, number: 3)
      cut.update_columns(published: true, started_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      feed = Feeds::Rounds.call(@t.reload)

      assert_equal ["1", "2", "Top 4"], feed[:rounds].pluck(:round)
      assert_equal "Top 4", feed[:latest]
      assert_nil feed[:roundTime]
      assert_nil feed[:rounds].last[:clock]
      assert_equal 4, feed[:rounds].last[:tables].sole[:players].size
      assert_nil Feeds::Info.call(@t)[:timerEnd]
    end

    test "multiplayer tables keep their keys, without games" do
      table = Feeds::Rounds.call(@t)[:rounds].first[:tables].first

      assert_equal %i[table status winner draw ended players], table.keys
    end

    test "1v1 tables carry the score: the winner's games, the draw's, or null before a result" do
      t = build_1v1_feed_tournament
      round1, round2 = Feeds::Rounds.call(t)[:rounds]

      assert_equal %i[table status winner draw ended players games], round1[:tables].first.keys
      assert_equal %w[2-1 1-1], round1[:tables].pluck(:games)
      assert_equal([2, 2], round1[:tables].map { |table| table[:players].size })
      assert_equal [nil, nil], round2[:tables].pluck(:games)
    end
  end
end
