# frozen_string_literal: true

require "test_helper"

module Standings
  class SnapshotTest < ActiveSupport::TestCase
    setup do
      @t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @t.update_columns(seed: 99, swiss_rounds_count: 3, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      @round1 = @t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => :draw })
    end

    test "ranks follow the public standings order" do
      Snapshot.call(@t, @round1)

      ranked = Feeds::Standings.ranked(@t).map(&:id)
      snapshot = @t.standings_snapshots.where(round_number: 1).order(:rank).pluck(:event_participant_id, :rank)
      assert_equal ranked, snapshot.map(&:first)
      assert_equal (1..8).to_a, snapshot.map(&:last)
    end

    test "running it again for the same round replaces the snapshot" do
      Snapshot.call(@t, @round1)
      first = @t.standings_snapshots.order(:rank).pluck(:event_participant_id, :rank)

      Snapshot.call(@t, @round1)

      assert_equal first, @t.standings_snapshots.order(:rank).pluck(:event_participant_id, :rank)
      assert_equal 8, @t.standings_snapshots.count
    end

    test "closing a round writes its snapshot before the next round is paired" do
      round2 = @t.rounds.create!(type: SwissRound, number: 2)
      round2.pods.each do |pod|
        pod.seatings.each_with_index do |seating, i|
          (i.zero? ? Win : Loss).create!(round: round2, event_participant_id: seating.event_participant_id)
        end
      end

      round2.update!(finished_at: Time.current, published: true)

      assert_equal 8, @t.standings_snapshots.where(round_number: 2).count
      assert @t.rounds.exists?(number: 3)
    end

    test "discard removes the reopened round and every later one" do
      Snapshot.call(@t, @round1)
      round2 = @t.rounds.create!(type: SwissRound, number: 2)
      Snapshot.call(@t, round2)

      Snapshot.discard(@t, 2)

      assert_equal [1], @t.standings_snapshots.distinct.pluck(:round_number)
    end

    test "movement compares the two latest snapshots; nil before the second" do
      Snapshot.call(@t, @round1)
      first, third = @t.standings_snapshots.where(rank: [1, 3]).order(:rank).map(&:event_participant)
      assert_nil first.movement_since_last_round

      swapped = { first.id => 3, third.id => 1 }
      @t.standings_snapshots.where(round_number: 1).find_each do |row|
        @t.standings_snapshots.create!(round_number: 2, event_participant_id: row.event_participant_id,
                                       rank: swapped.fetch(row.event_participant_id, row.rank))
      end

      movements = StandingsSnapshot.movements_for(@t.id)
      assert_equal(-2, first.movement_since_last_round)
      assert_equal 2, third.movement_since_last_round
      assert_equal [0] * 6, movements.except(first.id, third.id).values
    end
  end
end
