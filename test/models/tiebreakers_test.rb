# test/models/tiebreakers_test.rb
require "test_helper"

class TiebreakersTest < ActiveSupport::TestCase
  setup do
    @t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @t.update_columns(seed: 99, swiss_rounds_count: 2, top_cut_size: 0)
    @t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => :draw })
    @r1 = @t.rounds.first
    @winner = @r1.pods.find_by(number: 1).seatings.order(:order).first.event_participant
    @drawer = @r1.pods.find_by(number: 2).event_participants.first
  end

  test "components after one round" do
    assert_equal 7, @winner.match_points
    assert_equal 3, @winner.opponents_beaten
    assert_equal 3, @winner.unique_opponents
    assert_in_delta 1.0 / 7, @winner.opponents_win_rate, 0.0001   # three losers, each floored at 1/7
    assert_equal 1, @drawer.match_points
    assert_in_delta 1.0 / 7, @drawer.opponents_win_rate, 0.0001   # three drawers at 1/7 exactly
  end

  test "rank_score orders by points, then opponents win rate, then beaten, then unique, then salt" do
    others = @r1.pods.find_by(number: 2).event_participants.sort_by(&:rank_score).reverse
    assert_equal others.map(&:tiebreak_salt).sort.reverse, others.map(&:tiebreak_salt), "equal drawers fall back to the salt"
    assert_operator @winner.rank_score, :>, others.first.rank_score
  end

  test "a dropped player keeps counting as an opponent and the salt is stable" do
    loser = @r1.pods.find_by(number: 1).seatings.order(:order).last.event_participant
    loser.update_columns(dropped: true)
    assert_equal 3, @winner.reload.opponents_beaten
    assert_equal @winner.tiebreak_salt, EventParticipant.find(@winner.id).tiebreak_salt
  end
end
