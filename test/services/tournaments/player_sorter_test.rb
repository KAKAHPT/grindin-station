# frozen_string_literal: true

require "test_helper"

module Tournaments
  class PlayerSorterTest < ActiveSupport::TestCase
    test "deal sorts a points group by needed seat and deals it round-robin over its pods" do
      counts = {
        a: { 1 => 1, 2 => 0, 3 => 0, 4 => 0 }, b: { 1 => 1, 2 => 0, 3 => 0, 4 => 0 }, # need seat 2
        c: { 1 => 0, 2 => 1, 3 => 0, 4 => 0 }, d: { 1 => 0, 2 => 1, 3 => 0, 4 => 0 }, # need seat 1
        e: { 1 => 0, 2 => 0, 3 => 1, 4 => 0 }, f: { 1 => 0, 2 => 0, 3 => 1, 4 => 0 },
        g: { 1 => 0, 2 => 0, 3 => 0, 4 => 1 }, h: { 1 => 0, 2 => 0, 3 => 0, 4 => 1 }
      }
      dealt = PlayerSorter.deal(counts.keys, counts)
      pods = dealt.each_slice(4).to_a
      assert_equal 2, pods.size
      %i[a b].then { |pair| assert_not pods.any? { |pod| (pair - pod).empty? }, "seat-1 players a and b share a pod" }
      assert_equal %i[c e g a d f h b], dealt
    end

    test "equal-score players who need the same seat land in different pods; points order is kept" do
      t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      round = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => :draw, 2 => :draw })
      seat_one = round.seatings.where(order: 1).map(&:event_participant_id)
      sorter = PlayerSorter.new(t.rounds.find(round.id))

      paired = sorter.paired_players
      pods = paired.map(&:id).each_slice(4).to_a
      assert_equal 2, seat_one.size
      assert_not pods.any? { |pod| (seat_one - pod).empty? }, "both round-1 seat-1 players share a pod"
      assert_equal sorter.sorted_players.map(&:id).sort, paired.map(&:id).sort
      assert_equal paired.map(&:match_points).sort.reverse, paired.map(&:match_points)
    end

    test "random_players shuffles the whole field with the rng and deals it as one group" do
      t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      round = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => :draw })
      sorter = PlayerSorter.new(t.rounds.find(round.id))

      field = t.event_participants.sort_by(&:id).shuffle(random: Random.new(3))
      expected = PlayerSorter.deal(field, field.index_with(&:seat_counts)).map(&:id)
      assert_equal expected, sorter.random_players(Random.new(3)).map(&:id)
      assert_equal expected, sorter.random_players(Random.new(3)).map(&:id)
    end
  end
end
