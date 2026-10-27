# frozen_string_literal: true

require "test_helper"

class PodSeatingTest < ActiveSupport::TestCase
  test "swiss seatings are fair and audited; elimination seatings are ranked" do
    t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 2, top_cut_size: 4, seed: 123) # rubocop:disable Rails/SkipsModelValidations
    r1 = t.rounds.create!(type: SwissRound, number: 1)
    assert(r1.seatings.all? { |s| s.assigned_by == "fair" && s.cost.zero? })
    TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0 })
    r2 = t.rounds.create!(type: SwissRound, number: 2)
    r2.pods.each do |pod|
      first = pod.seatings.order(:order).first.event_participant
      assert_equal 0, first.seat_counts[1], "round 2 seat 1 must go to someone who never had it"
    end
    TournamentBuilder.play_round!(t, winners: { 1 => 1, 2 => 1 })
    cut = t.rounds.create!(type: SingleEliminationRound, number: 3)
    # Compare scores, not ids: players tied on rank_score may sit in either order.
    top_scores = t.event_participants.map(&:rank_score).sort.last(4).reverse
    assert_equal(top_scores, cut.pods.first.seatings.order(:order).map { |s| s.event_participant.rank_score })
    assert(cut.seatings.all? { |s| s.assigned_by == "ranked" })
  end

  test "seat_counts ignores byes and unfinished rounds" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.rounds.create!(type: SwissRound, number: 1)
    p = t.event_participants.first
    assert_equal({ 1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0 }, p.seat_counts)
  end

  test "the same seed seats the same players whatever order the candidates arrive in" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 2, top_cut_size: 0, seed: 123) # rubocop:disable Rails/SkipsModelValidations
    round = t.rounds.create!(type: SwissRound, number: 1)
    players = t.event_participants.to_a
    orders =
      [players, players.reverse].map do |candidates|
        pod = Pod.new(round: round, number: 1, size: 4)
        pod.candidates = candidates
        pod.fair_seatings
        pod.seatings.map(&:event_participant_id)
      end
    assert_equal orders.first, orders.last
  end

  test "seat_counts counts finished and published swiss seats, not the top cut" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 2, top_cut_size: 4, seed: 123) # rubocop:disable Rails/SkipsModelValidations
    r1 = t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0 })
    first = r1.pods.first.seatings.order(:order).first.event_participant
    assert_equal 1, first.seat_counts[1]
    t.event_participants.each { |p| assert_equal 1, p.seat_counts.values.sum }

    r2 = t.rounds.create!(type: SwissRound, number: 2)
    r2.update_columns(published: true) # rubocop:disable Rails/SkipsModelValidations
    t.event_participants.each { |p| assert_equal 2, p.seat_counts.values.sum, "published swiss round counts" }
    TournamentBuilder.play_round!(t, winners: { 1 => 0 })

    cut = t.rounds.create!(type: SingleEliminationRound, number: 3)
    cut.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
    assert_equal 4, cut.seatings.count
    t.event_participants.each { |p| assert_equal 2, p.seat_counts.values.sum, "top cut seats do not count" }
  end
end
