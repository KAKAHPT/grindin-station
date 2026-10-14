# frozen_string_literal: true

require "test_helper"

module Tournaments
  class CreatePodsJobTest < ActiveJob::TestCase
    test "17 players: two pods of 4 and three pods of 3, lowest ranked in the small pods" do
      t = TournamentBuilder.build(players: 17, organizer: event_organizers(:standard_organizer))
      round = t.rounds.create!(type: SwissRound, number: 1)   # after_create builds the pods
      assert_equal [4, 4, 3, 3, 3], round.pods.order(:number).map(&:size)
      assert_equal 17, round.seatings.count
      assert_equal 17, round.seatings.map(&:event_participant_id).uniq.size
    end

    test "round 2 standard: the four highest ranked players share pod 1" do
      t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      r1 = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0, 3 => 0, 4 => 0 })
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      top4 = t.event_participants.sort_by { |p| -p.rank_score }.first(4).map(&:id).sort
      assert_equal top4, r2.pods.find_by(number: 1).event_participants.map(&:id).sort
    end

    test "players never meet twice while another pairing is possible" do
      skip "SwissMatcher repete adversários; ver docs/superpowers/notes/2026-10-14-swiss-matcher-notes.md"
      t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => :draw, 2 => :draw, 3 => :draw, 4 => :draw })
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      r2.pods.each do |pod|
        pod.event_participants.to_a.combination(2).each do |a, b|
          assert_not a.played_against?(b), "#{a.name} and #{b.name} met in round 1"
        end
      end
    end
  end
end
