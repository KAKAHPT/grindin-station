# frozen_string_literal: true

require "test_helper"

module Scoring
  class PointWagerTest < ActiveSupport::TestCase
    setup do
      @league = LeagueBuilder.build(players: 5, organizer: event_organizers(:standard_organizer))
      @players = @league.event_participants.order(:created_at).to_a
    end

    test "the winner takes the four stakes" do
      play(@players.first(4), winner: @players[0])

      assert_equal [1300, 900, 900, 900, 1000], scores
    end

    test "stakes follow the points each player holds, in the order the games ended" do
      play(@players.first(4), winner: @players[0])
      play(@players.first(4), winner: @players[1])

      # second game: stakes 130 + 90 + 90 + 90 = 400
      assert_equal [1170, 1210, 810, 810, 1000], scores
    end

    test "a draw with the split rule shares the pot equally" do
      play(@players.first(4), winner: @players[0])
      play(@players.first(4), winner: :draw)

      assert_equal [1270, 910, 910, 910, 1000], scores
    end

    test "a draw with the lost rule gives the pot to nobody" do
      @league.update!(draw_rule: "lost")
      play(@players.first(4), winner: @players[0])
      play(@players.first(4), winner: :draw)

      assert_equal [1170, 810, 810, 810, 1000], scores
    end

    test "correcting the first game replays the later ones" do
      first = play(@players.first(4), winner: @players[0])
      play(@players.first(4), winner: @players[1])

      Results::Apply.call(pod: first, type: "Win", winner: @players[2], by: event_organizers(:standard_organizer).user)

      # first game to player 3 (1300), then stakes 90 + 90 + 130 + 90 = 400 to player 2
      assert_equal [810, 1210, 1170, 810, 1000], scores
    end

    test "the starting points and the percentage are the league's" do
      @league.update!(starting_points: 500, wager_percentage: 20)
      play(@players.first(4), winner: @players[3])

      assert_equal [400, 400, 400, 800, 500], scores
    end

    test "a player's report and one confirmation score the game and free the table" do
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))

      Results::Report.call(pod: pod, participant: @players[0], type: "Win", winner: @players[0])
      assert_equal [1000] * 5, scores
      Results::Confirm.call(pod: pod, participant: @players[1])

      assert_equal [1300, 900, 900, 900, 1000], scores
      assert_not_nil pod.round.reload.finished_at
      assert_not LeagueTableSeat.active.exists?(league_table: pod.league_table)
    end

    private

    def play(players, winner:)
      pod = LeagueBuilder.fill_table!(@league, players)
      if winner == :draw then Results::Apply.call(pod: pod, type: "Draw")
      else Results::Apply.call(pod: pod, type: "Win", winner: winner)
      end
      travel 1.minute
      pod
    end

    def scores = @players.map { |player| player.reload.league_score.to_i }
  end
end
