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

  test "opponents win rate decides before beaten, at full precision" do
    a, b = @r1.pods.find_by(number: 2).event_participants.map { |p| EventParticipant.find(p.id) }.first(2)
    assert_operator with_tiebreakers(a, owr: 0.143).rank_score, :>, with_tiebreakers(b, owr: 0.1429).rank_score,
                    "0.143 must outrank 0.1429"

    c, d = @r1.pods.find_by(number: 2).event_participants.map { |p| EventParticipant.find(p.id) }.first(2)
    assert_operator with_tiebreakers(c, owr: 0.2, beaten: 2).rank_score, :>, with_tiebreakers(d, owr: 0.2, beaten: 1).rank_score,
                    "with equal OWR, opponents beaten decides"
  end

  test "a dropped player keeps counting as an opponent and the salt is stable" do
    loser = @r1.pods.find_by(number: 1).seatings.order(:order).last.event_participant
    loser.update_columns(dropped: true)
    assert_equal 3, @winner.reload.opponents_beaten
    assert_equal @winner.tiebreak_salt, EventParticipant.find(@winner.id).tiebreak_salt
  end

  private

  # Pins the tiebreakers on one instance (Minitest 6 ships without stub); points and unique stay real and equal.
  def with_tiebreakers(participant, owr:, beaten: 0, salt: 0)
    participant.define_singleton_method(:opponents_win_rate) { owr }
    participant.define_singleton_method(:opponents_beaten) { beaten }
    participant.define_singleton_method(:tiebreak_salt) { salt }
    participant
  end
end
