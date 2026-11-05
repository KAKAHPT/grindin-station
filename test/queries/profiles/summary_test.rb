# frozen_string_literal: true

require "test_helper"

module Profiles
  class SummaryTest < ActiveSupport::TestCase
    test "counts events, cuts, wins and top 4, with win and conversion rates in whole percents" do
      rows = [row(position: 1, made_cut: true, wins: 2, losses: 1, draws: 0),
              row(position: 4, made_cut: true, wins: 0, losses: 2, draws: 1),
              row(position: 9, made_cut: false, wins: 0, losses: 1, draws: 1)]

      summary = Summary.call(rows)

      assert_equal [3, 2, 1, 2], [summary.events, summary.top_cuts, summary.wins, summary.top4]
      assert_equal 25, summary.win_rate
      assert_equal 67, summary.conversion_rate
    end

    test "nil positions count neither as wins nor top 4" do
      summary = Summary.call([row(position: nil)])

      assert_equal [0, 0], [summary.wins, summary.top4]
    end

    test "no rows: zero counts and nil rates" do
      summary = Summary.call([])

      assert_equal [0, 0, 0, 0], [summary.events, summary.top_cuts, summary.wins, summary.top4]
      assert_nil summary.win_rate
      assert_nil summary.conversion_rate
      assert_empty summary.commanders
    end

    test "no games played: nil win rate" do
      assert_nil Summary.call([row(wins: 0, losses: 0, draws: 0)]).win_rate
    end

    test "commanders: top 4 by count, then name A-Z, without nil" do
      names = ["Tymna", "Kinnan", "Kinnan", "Rograkh", "Rograkh", "Blue Farm", "Atraxa", nil, nil, nil]
      rows = names.map { |name| row(commander: name) }

      assert_equal [["Kinnan", 2], ["Rograkh", 2], ["Atraxa", 1], ["Blue Farm", 1]], Summary.call(rows).commanders
    end

    private

    # A History row with 1 win and 1 loss at 5th place unless given.
    def row(**attrs)
      record = { wins: 1, losses: 1, draws: 0 }.merge(attrs.slice(:wins, :losses, :draws))
      History::Row.new(event: nil, position: 5, participants: 16, seats: nil, decklist_visible: false, decklist: nil,
                       made_cut: false, cut_size: nil, commander: nil, organizer_name: "Org", format_line: "cEDH",
                       season: nil, round_seats: nil, **record, games: record.values.sum, **attrs.except(*record.keys))
    end
  end
end
