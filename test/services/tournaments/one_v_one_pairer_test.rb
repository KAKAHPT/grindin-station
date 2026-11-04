# frozen_string_literal: true

require "test_helper"

module Tournaments
  class OneVOnePairerTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    test "16 players over 5 rounds with seeded results never meet twice" do
      t = build(16, rounds: 5)
      rng = Random.new(42)
      met = Set.new
      5.times do |i|
        round = t.rounds.create!(type: SwissRound, number: i + 1)
        pairs(round).each do |pair|
          assert_not_includes met, pair.to_set, "rematch in round #{round.number}"
          met << pair.to_set
        end
        play!(t, round, rng)
      end
    end

    test "15 players: one bye per round, to the lowest-ranked player without a bye, never twice" do
      t = build(15, rounds: 5)
      rng = Random.new(7)
      bye_ids = []
      5.times do |i|
        expected = standings(t).rfind { |player| player.number_of_byes.zero? }
        round = t.rounds.create!(type: SwissRound, number: i + 1)
        byes = round.byes.to_a
        assert_equal 1, byes.size
        assert_equal expected.id, byes.first.event_participant_id
        assert_equal [2, 0, 0], byes.first.games
        assert_not_includes round.seatings.map(&:event_participant_id), expected.id
        bye_ids << expected.id
        play!(t, round, rng)
      end
      assert_equal bye_ids.uniq, bye_ids
    end

    test "an odd points group sends its lowest-ranked player down; the other groups pair inside" do
      t = build(12, rounds: 5)
      2.times do |i|
        round = t.rounds.create!(type: SwissRound, number: i + 1)
        TournamentBuilder.play_1v1_round!(t, scores: round.pods.pluck(:number).index_with([2, 0]))
      end
      ranked = standings(t)
      leaders = ranked.select { |player| player.match_points == 6 }
      assert_equal 3, leaders.size

      round = repair_free_round(t, 3)
      points = ranked.to_h { |player| [player.id, player.match_points] }
      by_player = pairs(round).flat_map { |pair| [pair, pair.reverse] }.to_h
      assert_equal leaders[1].id, by_player[leaders[0].id]
      assert_equal 3, points[by_player[leaders[2].id]]
      mixed = pairs(round).count { |a, b| points[a] != points[b] }
      assert_equal 2, mixed, "only the pair-down crosses groups (6 v 3, then the odd 3-point group's 3 v 0)"
    end

    test "with repair on, the 12-player pair-down crosses groups only where it must (6 v 3, then 3 v 0)" do
      t = build(12, rounds: 5)
      2.times do |i|
        round = t.rounds.create!(type: SwissRound, number: i + 1)
        TournamentBuilder.play_1v1_round!(t, scores: round.pods.pluck(:number).index_with([2, 0]))
      end
      points = standings(t).to_h { |player| [player.id, player.match_points] }
      round = t.rounds.create!(type: SwissRound, number: 3)
      crossed = pairs(round).map { |pair| pair.map { |id| points[id] }.sort.reverse }.reject { |a, b| a == b }
      assert_equal [[3, 0], [6, 3]], crossed.sort
      assert_equal 0, RematchRepair.new(round, max_point_gap: 0).repair!
    end

    test "a non-last round pairs inside a group in random order, not top-down" do
      t = build(8, rounds: 4)
      round = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(t, scores: round.pods.pluck(:number).index_with([2, 0]))
      random =
        (1..6).any? do |seed|
          t.update_columns(seed: seed) # rubocop:disable Rails/SkipsModelValidations
          t.rounds.find_by(number: 2)&.destroy!
          top_down = standings(t).map(&:id).each_slice(2).map(&:sort)
          pairs(repair_free_round(t.reload, 2)).map(&:sort) != top_down
        end
      assert random, "six seeds all paired the groups top-down"
    end

    test "when everyone already had a bye, the lowest-ranked player gets it" do
      t = build(3, rounds: 4)
      rng = Random.new(5)
      3.times { |i| play!(t, t.rounds.create!(type: SwissRound, number: i + 1), rng) }
      assert(standings(t).all? { |player| player.number_of_byes == 1 })
      lowest = standings(t).last
      round = t.rounds.create!(type: SwissRound, number: 4)
      assert_equal [lowest.id], round.byes.pluck(:event_participant_id)
    end

    test "the last swiss round pairs each group top-down: rank 1 plays rank 2" do
      t = build(8, rounds: 3)
      2.times do |i|
        round = t.rounds.create!(type: SwissRound, number: i + 1)
        TournamentBuilder.play_1v1_round!(t, scores: round.pods.pluck(:number).index_with([2, 0]))
      end
      ranked = standings(t)
      assert_equal [6, 6, 3], ranked.first(3).map(&:match_points)
      round = repair_free_round(t, 3)
      expected = ranked.map(&:id).each_slice(2).map(&:sort)
      assert_equal expected, pairs(round).map(&:sort), "1v2, 3v4, 5v6, 7v8"
    end

    test "the same seed gives the same pairings and seats" do
      t = build(10, rounds: 4)
      t.update_columns(seed: 1234) # rubocop:disable Rails/SkipsModelValidations
      first = seats(t.rounds.create!(type: SwissRound, number: 1))
      t.rounds.find_by!(number: 1).destroy!
      assert_equal first, seats(t.rounds.create!(type: SwissRound, number: 1))
      play!(t, t.rounds.find_by!(number: 1), Random.new(3))
      second = seats(t.rounds.create!(type: SwissRound, number: 2))
      t.rounds.find_by!(number: 2).destroy!
      assert_equal second, seats(t.rounds.create!(type: SwissRound, number: 2))
    end

    test "pods hold two players with randomly assigned seats 1 and 2" do
      t = build(9, rounds: 4)
      round = t.rounds.create!(type: SwissRound, number: 1)
      pods = round.pods.includes(:seatings).order(:number)
      assert_equal (1..4).to_a, pods.map(&:number)
      pods.each do |pod|
        assert_equal 2, pod.size
        assert_equal [1, 2], pod.seatings.map(&:order)
        assert_equal %w[random random], pod.seatings.map(&:assigned_by)
      end
    end

    test "raises when the round already has pods" do
      t = build(4, rounds: 2)
      round = t.rounds.create!(type: SwissRound, number: 1)
      assert_raises(ArgumentError) { OneVOnePairer.call(round) }
    end

    test "raises when only a bye is left on the round" do
      t = build(5, rounds: 2)
      round = t.rounds.create!(type: SwissRound, number: 1)
      round.pods.destroy_all
      assert_equal 1, round.all_results.count
      assert_raises(ArgumentError) { OneVOnePairer.call(round.reload) }
    end

    private

    def build(players, rounds:)
      t = TournamentBuilder.build(players: players, organizer: event_organizers(:standard_organizer),
                                  format: "one_v_one")
      t.update_columns(swiss_rounds_count: rounds) # rubocop:disable Rails/SkipsModelValidations
      t
    end

    # The round paired by the grouping rules alone: RematchRepair may legitimately move players on random ids.
    def repair_free_round(tournament, number)
      round = tournament.rounds.create!(type: SwissRound, number: number)
      round.pods.destroy_all
      round.all_results.destroy_all
      Class.new(OneVOnePairer) { def repair_rematches! = nil }.call(round.reload)
      round
    end

    def standings(tournament)
      EventParticipant.standings_for(tournament).sort_by { |player| [-player.rank_score, player.id] }
    end

    def pairs(round)
      round.pods.includes(:seatings).order(:number).map { |pod| pod.seatings.map(&:event_participant_id) }
    end

    def seats(round) = pairs(round)

    def play!(tournament, round, rng)
      scores = round.pods.pluck(:number).index_with { [[2, 0], [0, 2], [2, 1], [1, 2], [1, 1]].sample(random: rng) }
      TournamentBuilder.play_1v1_round!(tournament, scores: scores)
    end
  end
end
