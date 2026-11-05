# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Exports
  class PairingsTest < ActiveSupport::TestCase
    include ExportTournament

    HEADER = %w[Table Player1 Player2 Player3 Player4 Player5].freeze

    test "multiplayer: one row per table, players in seat order" do
      t = build_export_tournament
      round = t.rounds.find_by!(number: 1)
      pod = round.pods.find_by!(number: 3)

      rows = nil
      without_n_plus_one { rows = parse_export(Exports::Pairings.call(t, round: round)) }

      assert_equal HEADER, rows.first
      assert_equal 5, rows.size
      assert_equal ["3", *pod.seatings.map { |seating| seating.event_participant.name }, nil], rows[3]
    end

    test "1v1: two players per table, the bye is not a table" do
      t = build_export_1v1_tournament
      round = t.rounds.first

      rows = parse_export(Exports::Pairings.call(t, round: round))

      assert_equal 3, rows.size
      assert_equal %w[1 2], rows.drop(1).map(&:first)
      assert(rows.drop(1).all? { |row| row[1].present? && row[2].present? && row[3..].all?(&:nil?) })
    end
  end
end
