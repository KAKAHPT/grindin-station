# frozen_string_literal: true

# test/services/tournaments/rematch_repair_test.rb
require "test_helper"

module Tournaments
  class RematchRepairTest < ActiveSupport::TestCase
    test "removes every rematch when a clean arrangement exists (16 players after an all-draw round)" do
      t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => :draw, 2 => :draw, 3 => :draw, 4 => :draw })
      r2 = t.rounds.create!(type: SwissRound, number: 2) # job runs strategy + repair
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
      t.update_columns(swiss_rounds_count: 2) if t.has_attribute?(:swiss_rounds_count) # rubocop:disable Rails/SkipsModelValidations
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0 })
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      assert_equal 4, r2.seatings.count
      assert_equal 6, rematch_pairs(r2)
    end

    test "repair! returns the Integer count of rematch pairs left" do
      round, pod1, pod2 = two_pods_after_round_one
      left = RematchRepair.new(round, max_point_gap: Float::INFINITY).repair!
      assert_kind_of Integer, left
      assert_equal left, candidate_rematch_pairs([pod1, pod2])
    end

    test "max_point_gap: 0 refuses an improving swap across points groups" do
      round, pod1, pod2 = two_pods_after_round_one # pod 1: 7, 0, 0, 0 points; pod 2: 1, 1, 1, 1
      before = [pod1.candidates.dup, pod2.candidates.dup]

      assert_equal 12, RematchRepair.new(round, max_point_gap: 0).repair!
      assert_equal before, [pod1.candidates, pod2.candidates]

      assert_operator RematchRepair.new(round, max_point_gap: 1).repair!, :<, 12, "a 0 <-> 1 point swap improves"
      assert_includes pod1.candidates.map(&:match_points), 7, "the 7-point player is 6 points from everyone in pod 2"
    end

    test "the swap loop stops at MAX_SWAPS_PER_POD swaps per pod" do
      round, = two_pods_after_round_one
      endless =
        Class.new(RematchRepair) do
          attr_reader :swaps

          private

          def swap_improves?(*) = true
          def swap!(*) = (@swaps = @swaps.to_i + 1)
        end
      repair = endless.new(round, max_point_gap: Float::INFINITY)

      assert_equal 12, repair.repair!
      assert_equal RematchRepair::MAX_SWAPS_PER_POD * 2, repair.swaps
    end

    private

    # Round 1 of 8 players (pod 1: one winner, pod 2: a draw), then an unsaved round 2 whose pods hold
    # the same four players again as candidates: 12 rematch pairs.
    def two_pods_after_round_one
      t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      r1 = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => :draw })
      players = t.event_participants.reload.index_by(&:id)
      round = SwissRound.new(event: t, number: 2)
      [round, *r1.pods.order(:number).map { |old_pod| rebuild_pod(round, old_pod, players) }]
    end

    def rebuild_pod(round, old_pod, players)
      round.pods.build(number: old_pod.number, size: 4).tap do |pod|
        pod.candidates = old_pod.seatings.map { |seating| players.fetch(seating.event_participant_id) }
      end
    end

    def candidate_rematch_pairs(pods)
      pods.sum { |pod| pod.candidates.combination(2).count { |a, b| a.played_against?(b) } }
    end

    def rematch_pairs(round)
      round.pods.sum { |pod| pod.event_participants.to_a.combination(2).count { |a, b| a.played_against?(b) } }
    end
  end
end
