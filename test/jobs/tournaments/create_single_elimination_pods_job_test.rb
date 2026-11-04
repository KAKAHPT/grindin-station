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
      t, seeds = one_v_one_top_eight
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      assert_equal [[1, 8], [2, 7], [3, 6], [4, 5]].map { |pair| pair.map { |seed| seeds[seed - 1] } }, bracket(cut)
      assert_equal %w[ranked], cut.seatings.map(&:assigned_by).uniq
      assert_equal seeds[8..].sort, cut.results.where(type: "Eliminated").pluck(:event_participant_id).sort
    end

    test "1v1 bracket: the next round pairs the winners of pods i and k+1-i" do
      t, seeds = one_v_one_top_eight
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      { 8 => 1, 2 => 7, 3 => 6, 5 => 4 }.each do |winner, loser|
        Advance.create!(round: cut, event_participant_id: seeds[winner - 1])
        Eliminated.create!(round: cut, event_participant_id: seeds[loser - 1])
      end
      cut.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
      semis = t.rounds.create!(type: SingleEliminationRound, number: 3)
      assert_equal [[5, 8], [2, 3]].map { |pair| pair.map { |seed| seeds[seed - 1] } }, bracket(semis)
    end

    private

    # 10 players, one 1v1 swiss round, Top 8; seeds = participant ids by rank (1st first).
    def one_v_one_top_eight
      t = TournamentBuilder.build(players: 10, organizer: event_organizers(:standard_organizer), format: "one_v_one")
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 8) # rubocop:disable Rails/SkipsModelValidations
      round = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(t, scores: round.pods.pluck(:number).index_with([2, 0]))
      [t, EventParticipant.standings_for(t).sort_by { |player| -player.rank_score }.map(&:id)]
    end

    def bracket(round)
      round.pods.includes(:seatings).order(:number).map { |pod| pod.seatings.map(&:event_participant_id) }
    end
  end
end
