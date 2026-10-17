require "test_helper"

class PodSeatingTest < ActiveSupport::TestCase
  test "swiss seatings are fair and audited; elimination seatings are ranked" do
    t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 2, top_cut_size: 4, seed: 123)
    r1 = t.rounds.create!(type: SwissRound, number: 1)
    assert r1.seatings.all? { |s| s.assigned_by == "fair" && s.cost == 0 }
    TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0 })
    r2 = t.rounds.create!(type: SwissRound, number: 2)
    r2.pods.each do |pod|
      first = pod.seatings.order(:order).first.event_participant
      assert_equal 0, first.seat_counts[1], "round 2 seat 1 must go to someone who never had it"
    end
    TournamentBuilder.play_round!(t, winners: { 1 => 1, 2 => 1 })
    cut = t.rounds.create!(type: SingleEliminationRound, number: 3)
    # Compare scores, not ids: players tied on rank_score may sit in either order.
    top_scores = t.event_participants.map(&:rank_score).sort.reverse.first(4)
    assert_equal top_scores, cut.pods.first.seatings.order(:order).map { |s| s.event_participant.rank_score }
    assert cut.seatings.all? { |s| s.assigned_by == "ranked" }
  end

  test "seat_counts ignores byes and unfinished rounds" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.rounds.create!(type: SwissRound, number: 1)
    p = t.event_participants.first
    assert_equal({ 1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0 }, p.seat_counts)
  end
end
