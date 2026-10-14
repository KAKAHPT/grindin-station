# test/services/tournaments/rematch_repair_test.rb
require "test_helper"

class Tournaments::RematchRepairTest < ActiveSupport::TestCase
  test "removes every rematch when a clean arrangement exists (16 players after an all-draw round)" do
    t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => :draw, 2 => :draw, 3 => :draw, 4 => :draw })
    r2 = t.rounds.create!(type: SwissRound, number: 2)   # job runs strategy + repair
    assert_equal 0, rematch_pairs(r2)
  end

  test "standard rounds never move a player out of their points group" do
    t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 2) # rubocop:disable Rails/SkipsModelValidations -- round 2 of 2 is standard
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0, 3 => 0, 4 => 0 })
    r2 = t.rounds.create!(type: SwissRound, number: 2)
    winners = t.event_participants.select { |p| p.match_points == 7 }.map(&:id).sort
    assert_equal winners, r2.pods.find_by(number: 1).event_participants.map(&:id).sort
    assert_equal 0, rematch_pairs(r2)
  end

  test "an unavoidable rematch still seats everyone and terminates (4 players, round 2)" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 2) if t.has_attribute?(:swiss_rounds_count)
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0 })
    r2 = t.rounds.create!(type: SwissRound, number: 2)
    assert_equal 4, r2.seatings.count
    assert_equal 6, rematch_pairs(r2)
  end

  private

  def rematch_pairs(round)
    round.pods.sum { |pod| pod.event_participants.to_a.combination(2).count { |a, b| a.played_against?(b) } }
  end
end
