# frozen_string_literal: true

require "test_helper"

module Tournaments
  class CreateSingleEliminationPodsJobTest < ActiveJob::TestCase
    test "top 13: seed 1 advances, seeds 2-13 play three pods, the rest are eliminated" do
      t = TournamentBuilder.build(players: 32, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 13) # rubocop:disable Rails/SkipsModelValidations
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: (1..8).index_with(0))
      # One swiss round leaves ties (the 8 winners score alike, as do the 24 losers) that the job breaks at random,
      # so seeds are compared by their pre-cut rank score rather than by id.
      score = t.event_participants.to_h { |p| [p.id, p.rank_score] }
      seeds = score.values.sort.reverse
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      assert_equal 3, cut.pods.count
      advanced = cut.results.where(type: "Advance").pluck(:event_participant_id)
      seated = cut.seatings.map(&:event_participant_id)
      assert_equal([seeds.first], advanced.map { |id| score[id] })
      assert_equal 19, cut.results.where(type: "Eliminated").count
      assert_equal seeds[1..12], seated.map { |id| score[id] }.sort.reverse
      assert_empty advanced & seated
    end

    test "top 40 has three elimination rounds" do
      t = TournamentBuilder.build(players: 130, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 40) # rubocop:disable Rails/SkipsModelValidations
      assert_equal 3, t.number_of_single_elimination_rounds
      assert_equal "Quarter-Finals", t.single_elimination_round_name(2)
    end

    test "a tournament without a top cut raises a clear ArgumentError" do
      t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations

      error = assert_raises(ArgumentError) { t.rounds.create!(type: SingleEliminationRound, number: 2) }
      assert_equal "tournament has no top cut", error.message
    end

    test "1v1 top 8: seeds 1v8, 2v7, 3v6, 4v5 in pod order, higher seed in seat 1, the rest eliminated" do
      t = one_v_one_top_eight
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      seeds = seeds_from(cut)
      score = t.event_participants.to_h { |p| [p.id, p.rank_score] }
      assert_equal 4, cut.pods.count
      assert_equal 8, seeds.size
      # Seed order follows the ranking (ties on the rank score are broken by the job, at random).
      assert_equal(score.values.sort.last(8).reverse, seeds.map { |id| score[id] })
      assert_equal %w[ranked], cut.seatings.map(&:assigned_by).uniq
      eliminated = cut.results.where(type: "Eliminated").pluck(:event_participant_id)
      assert_equal 2, eliminated.size
      assert_empty eliminated & seeds
      assert_operator eliminated.map { |id| score[id] }.max, :<=, score[seeds.last]
    end

    test "1v1 bracket: the next round pairs the winners of pods i and k+1-i" do
      t = one_v_one_top_eight
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      seeds = seeds_from(cut)
      close_cut!(cut, seeds, { 8 => 1, 2 => 7, 3 => 6, 5 => 4 })
      semis = t.rounds.create!(type: SingleEliminationRound, number: 3)
      assert_equal [[5, 8], [2, 3]].map { |pair| pair.map { |seed| seeds[seed - 1] } }, bracket(semis)
    end

    test "1v1 top 8 with 7 players: seed 1 advances by walkover, then meets the 4/5 winner" do
      t = one_v_one_top_eight(dropped: 3)
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      seeds = seeds_from(cut)
      assert_equal 7, seeds.size
      assert_equal 3, cut.pods.count
      assert_equal [seeds[0]], cut.byes.pluck(:event_participant_id)
      assert_equal seeds[0], t.event_participants.reject(&:dropped).max_by(&:rank_score).id
      assert_equal 0, cut.results.where(type: "Eliminated").count

      close_cut!(cut, seeds, { 2 => 7, 3 => 6, 4 => 5 })
      semis = t.rounds.create!(type: SingleEliminationRound, number: 3)
      assert_equal [[1, 4], [2, 3]].map { |pair| pair.map { |seed| seeds[seed - 1] } }, bracket(semis)
    end

    test "1v1 bracket: a winner who dropped leaves a walkover for the k+1-i winner" do
      t = one_v_one_top_eight
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      seeds = seeds_from(cut)
      close_cut!(cut, seeds, { 8 => 1, 2 => 7, 3 => 6, 5 => 4 })
      t.event_participants.find(seeds[7]).update_columns(dropped: true) # rubocop:disable Rails/SkipsModelValidations
      semis = t.rounds.create!(type: SingleEliminationRound, number: 3)
      assert_equal [[seeds[1], seeds[2]]], bracket(semis)
      assert_equal [seeds[4]], semis.byes.pluck(:event_participant_id)
    end

    private

    # 10 players, one 1v1 swiss round, Top 8, then `dropped` of them drop.
    def one_v_one_top_eight(dropped: 0)
      t = TournamentBuilder.build(players: 10, organizer: event_organizers(:standard_organizer), format: "one_v_one")
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 8) # rubocop:disable Rails/SkipsModelValidations
      round = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(t, scores: round.pods.pluck(:number).index_with([2, 0]))
      t.event_participants.first(dropped).each { |p| p.update_columns(dropped: true) } # rubocop:disable Rails/SkipsModelValidations
      t
    end

    # The seeds as the job dealt them (1st first): byes, then pod i's seat 1 is seed i and its seat 2 is seed
    # k+1-i. Read back from the cut because ties on the rank score are broken at random by the job.
    def seeds_from(cut)
      pairs = bracket(cut)
      cut.byes.pluck(:event_participant_id) + pairs.map(&:first) + pairs.map(&:last).reverse
    end

    # Records { winner seed => loser seed } as Advance/Eliminated and closes the cut round.
    def close_cut!(cut, seeds, results)
      results.each do |winner, loser|
        Advance.create!(round: cut, event_participant_id: seeds[winner - 1])
        Eliminated.create!(round: cut, event_participant_id: seeds[loser - 1])
      end
      cut.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
    end

    def bracket(round)
      round.pods.includes(:seatings).order(:number).map do |pod|
        pod.seatings.sort_by(&:order).map(&:event_participant_id)
      end
    end
  end
end
