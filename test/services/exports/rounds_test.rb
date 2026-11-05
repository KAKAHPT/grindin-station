# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Exports
  class RoundsTest < ActiveSupport::TestCase
    include ExportTournament

    HEADER = %w[round table seat player email result gamesWon gamesLost gamesDrawn].freeze

    test "multiplayer: one row per seat of every round" do
      t = build_export_tournament
      first_round = t.rounds.find_by!(number: 1)
      winner = first_round.pods.find_by!(number: 2).seatings.second.event_participant

      rows = nil
      without_n_plus_one { rows = parse_export(Exports::Rounds.call(t)) }

      assert_equal HEADER, rows.first
      assert_equal 33, rows.size
      assert_includes rows, ["1", "2", "2", winner.name, winner.player.reporting_email, "win", "0", "0", "0"]
      assert_equal(%w[draw] * 4, rows.select { |row| row[0] == "1" && row[1] == "3" }.pluck(5))
      assert_equal %w[1 2], rows.drop(1).map(&:first).uniq
    end

    test "1v1: games and the bye, with no table or seat" do
      t = build_export_1v1_tournament
      bye = Result.find_by!(type: "Advance", round: t.rounds.first).event_participant

      rows = nil
      without_n_plus_one { rows = parse_export(Exports::Rounds.call(t)) }

      assert_equal 6, rows.size
      assert_includes rows, ["1", nil, nil, bye.name, bye.player.reporting_email, "bye", "2", "0", "0"]
      winner = rows.find { |row| row[1] == "1" && row[5] == "win" }
      assert_equal %w[2 1 0], winner[6, 3]
    end

    test "a cut round uses the cut name and keeps advance / eliminated" do
      t = build_export_tournament
      cut = t.rounds.create!(type: SingleEliminationRound, number: 3)
      TournamentBuilder.play_round!(t, winners: {})
      cut.pods.each do |pod|
        pod.seatings.each_with_index do |seating, i|
          (i.zero? ? Advance : Eliminated).create!(round: cut, event_participant_id: seating.event_participant_id)
        end
      end

      rows = parse_export(Exports::Rounds.call(t.reload)).reject { |row| row[0].match?(/\A\d+\z/) }.drop(1)

      assert_equal [t.single_elimination_round_name(3)], rows.map(&:first).uniq
      assert_equal %w[advance eliminated], rows.pluck(5).uniq.sort
    end
  end
end
