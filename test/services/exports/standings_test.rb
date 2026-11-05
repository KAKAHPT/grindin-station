# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Exports
  class StandingsTest < ActiveSupport::TestCase
    include ExportTournament

    test "multiplayer: header, standings order, dropped players last with yes" do
      t = build_export_tournament
      leader = Feeds::Standings.ranked(t).first
      dropped = participant_named(t, Feeds::Standings.ranked(t).second.name)
      dropped.update_columns(dropped: true) # rubocop:disable Rails/SkipsModelValidations

      rows = nil
      without_n_plus_one { rows = parse_export(Exports::Standings.call(t.reload)) }

      assert_equal %w[standing name email points wins draws losses byes winRate opponentWinRate dropped], rows.first
      assert_equal 17, rows.size
      first = rows.second
      leader = EventParticipant.standings_for(t).find { |p| p.id == leader.id }
      assert_equal ["1", leader.name, leader.player.reporting_email, leader.match_points.to_s,
                    leader.number_of_wins.to_s, leader.number_of_draws.to_s, leader.number_of_losses.to_s, "0",
                    format("%.3f", leader.win_rate), format("%.3f", leader.opponents_win_rate), "no"], first
      assert_equal ["16", dropped.name], rows.last.first(2)
      assert_equal "yes", rows.last.last
      assert_equal (1..16).map(&:to_s), rows.drop(1).map(&:first)
      assert(rows.drop(1).all? { |row| row[8].match?(/\A\d\.\d{3}\z/) })
    end

    test "1v1: omw, gw and ogw instead of the win rates; a bye counts" do
      t = build_export_1v1_tournament

      rows = nil
      without_n_plus_one { rows = parse_export(Exports::Standings.call(t)) }

      assert_equal %w[standing name email points wins draws losses byes omw gw ogw dropped], rows.first
      assert_equal 6, rows.size
      bye = Result.find_by!(type: "Advance", round: t.rounds.first).event_participant
      row = rows.find { |r| r[1] == bye.name }
      assert_equal %w[0 0 0 1], row[4, 4]
      assert(row[8, 3].all? { |rate| rate.match?(/\A\d\.\d{3}\z/) })
    end
  end
end
