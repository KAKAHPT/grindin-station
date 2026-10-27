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
  end
end
