# frozen_string_literal: true

require "test_helper"

module Tournaments
  class CreatePodsJobTest < ActiveJob::TestCase
    test "17 players: two pods of 4 and three pods of 3, every player seated once" do
      t = TournamentBuilder.build(players: 17, organizer: event_organizers(:standard_organizer))
      round = t.rounds.create!(type: SwissRound, number: 1) # after_create builds the pods
      assert_equal [4, 4, 3, 3, 3], round.pods.order(:number).map(&:size)
      assert_equal 17, round.seatings.count
      assert_equal 17, round.seatings.map(&:event_participant_id).uniq.size
    end

    test "round 2 standard: the four highest ranked players share pod 1" do
      t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 2) # rubocop:disable Rails/SkipsModelValidations -- round 2 of 2 is standard
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0, 3 => 0, 4 => 0 })
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      top4 = t.event_participants.sort_by { |p| -p.rank_score }.first(4).map(&:id).sort
      assert_equal top4, r2.pods.find_by(number: 1).event_participants.map(&:id).sort
    end

    test "players never meet twice while another pairing is possible" do
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

    test "spread round (20 players) has no rematches" do
      t = TournamentBuilder.build(players: 20, organizer: event_organizers(:standard_organizer))
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => :draw, 2 => :draw, 3 => :draw, 4 => :draw, 5 => :draw })
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      assert_equal :spread, t.rounds_info[:rounds][1][:swiss_round]
      assert_equal 20, r2.seatings.count
      rematches =
        r2.pods.sum do |pod|
          pod.event_participants.to_a.combination(2).count { |a, b| a.played_against?(b) }
        end
      assert_equal 0, rematches
    end
  end
end
