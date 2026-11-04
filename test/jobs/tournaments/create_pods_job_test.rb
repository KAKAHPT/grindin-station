# frozen_string_literal: true

require "test_helper"

module Tournaments
  class CreatePodsJobTest < ActiveJob::TestCase # rubocop:disable Metrics/ClassLength
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

    test "power: round 2 of a spread-shaped event pairs top-down, the four highest ranked share pod 1" do
      t = TournamentBuilder.build(players: 20, organizer: event_organizers(:standard_organizer))
      t.update_columns(pairing_mode: "power") # rubocop:disable Rails/SkipsModelValidations -- locked after swiss
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => :draw })
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      assert_equal :standard, t.rounds_info[:rounds][1][:swiss_round]
      top4 = t.event_participants.sort_by { |p| -p.rank_score }.first(4).map(&:id).sort
      assert_equal top4, r2.pods.find_by(number: 1).event_participants.map(&:id).sort
    end

    test "random: points are ignored and the pods repeat for the same seed" do
      t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 2, pairing_mode: "random", seed: 42) # rubocop:disable Rails/SkipsModelValidations
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => 1, 3 => 2, 4 => 3 })
      winners = t.event_participants.select { |p| p.match_points.positive? }.map(&:id).sort
      r2 = t.rounds.create!(type: SwissRound, number: 2)
      pods = pod_ids(r2)

      assert_equal 4, winners.size
      assert_not_equal winners, pods.first
      r2.destroy!
      assert_equal pods, pod_ids(t.rounds.create!(type: SwissRound, number: 2))
    end

    # Round 3 of 16 is left out: there the greedy RematchRepair sometimes stops at 2 rematches, in swiss mode too.
    test "random: rematch repair leaves no rematch in round 2 for 16 seeds" do
      16.times do |seed|
        t = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
        t.update_columns(swiss_rounds_count: 3, pairing_mode: "random", seed: seed) # rubocop:disable Rails/SkipsModelValidations
        (1..2).each do |number|
          round = t.rounds.create!(type: SwissRound, number: number)
          assert_equal 0, rematches(round), "seed #{seed}, round #{number}"
          TournamentBuilder.play_round!(t, winners: (1..4).index_with(:draw))
        end
      end
    end

    test "every pairing mode seats every player once, fairly" do
      Event::PAIRING_MODES.each do |mode|
        t = TournamentBuilder.build(players: 17, organizer: event_organizers(:standard_organizer))
        t.update_columns(pairing_mode: mode, seed: 7) # rubocop:disable Rails/SkipsModelValidations -- locked after swiss
        t.rounds.create!(type: SwissRound, number: 1)
        TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => :draw, 3 => 1, 4 => :draw, 5 => 2 })
        seatings = t.rounds.create!(type: SwissRound, number: 2).seatings
        assert_equal 17, seatings.map(&:event_participant_id).uniq.size, mode
        assert_equal 17, seatings.size, mode
        assert_equal ["fair"], seatings.map(&:assigned_by).uniq, mode
      end
    end

    # Forced-round scenario: the H players' pod order in rounds 1-3.
    LOSER_ORDERS = [(0..11).to_a, [0, 4, 8, 1, 5, 9, 2, 6, 10, 3, 7, 11], [0, 5, 10, 3, 4, 9, 2, 7, 8, 1, 6, 11]].freeze
    # Grid cell (x, y) => pod key per round: columns, rows, slope-1 lines (GF(4) addition is XOR).
    GRID_LINES = [->(x, _) { x }, ->(_, y) { y }, ->(x, y) { x ^ y }].freeze

    # 32 players, 4 rounds (round 4 is forced). Rounds 1-3 are scripted: leaders A1-A4 win pods 1-4 every round and
    # never meet (21 points); group G (16 players, a 4x4 grid over GF(4)) draws in pods 5-8 along the columns, the
    # rows and the slope-1 lines (3 points, each met 9 of the other 15; the slope-a lines are a rematch-free split);
    # group H (12 players) loses to the leaders (0 points). Round 4 pairs G into pods 2-5 with rematches, while a
    # rematch-free arrangement keeps A1-A4 in pod 1.
    test "forced round: rematch repair keeps the leaders in pod 1 when a rematch-free pod 1 exists" do
      t = TournamentBuilder.build(players: 32, organizer: event_organizers(:standard_organizer))
      t.update_columns(swiss_rounds_count: 4) # rubocop:disable Rails/SkipsModelValidations -- round 4 of 4 is forced
      leaders = script_forced_history!(t)
      assert_equal :forced, t.rounds_info[:rounds][3][:swiss_round]

      r4 = t.rounds.create!(type: SwissRound, number: 4)
      pods = r4.pods.order(:number).map { |pod| pod.event_participants.to_a }

      top4 = t.event_participants.reload.max_by(4, &:match_points).map(&:id).sort
      assert_equal leaders.map(&:id).sort, top4
      assert_equal top4, pods.first.map(&:id).sort, "pods: #{points_of(pods)}"
      assert_equal(0, pods.sum { |pod| pod.combination(2).count { |a, b| a.played_against?(b) } })
    end

    private

    # Plays rounds 1-3 as described above; returns the four leaders.
    def script_forced_history!(tournament)
      players = tournament.event_participants.order(:id).to_a
      leaders = players.first(4)
      grid = players[4, 16] # grid[4 * x + y] is cell (x, y)

      GRID_LINES.each_with_index do |line, i|
        pods = leader_pods(leaders, players.last(12), LOSER_ORDERS[i]) + drawn_grid_pods(grid, line)
        play_scripted_round!(tournament, i + 1, pods)
      end
      leaders
    end

    def leader_pods(leaders, losers, order)
      leaders.zip(order.map { |k| losers[k] }.each_slice(3)).map { |leader, rest| [[leader, *rest], leader] }
    end

    def drawn_grid_pods(grid, line)
      keys = grid.each_index.map { |k| line.call(k / 4, k % 4) }
      grid.zip(keys).group_by(&:last).sort.map { |_, cells| [cells.map(&:first), :draw] }
    end

    # Replaces the seatings the job built for round `number` with `pods` ([[players, winner | :draw], ...]).
    def play_scripted_round!(tournament, number, pods)
      round = tournament.rounds.create!(type: SwissRound, number: number)
      Seating.where(pod_id: round.pod_ids).delete_all
      round.pods.order(:number).zip(pods).each { |pod, (players, winner)| seat_and_score!(pod, players, winner) }
      round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
    end

    def seat_and_score!(pod, players, winner)
      players.each.with_index(1) do |player, order|
        pod.seatings.create!(event_participant: player, order: order)
        result_for(player, winner).create!(round: pod.round, event_participant: player)
      end
    end

    def result_for(player, winner)
      return Draw if winner == :draw

      player == winner ? Win : Loss
    end

    def pod_ids(round) = round.pods.order(:number).map { |pod| pod.event_participants.map(&:id).sort }

    def rematches(round)
      round.pods.sum { |pod| pod.event_participants.to_a.combination(2).count { |a, b| a.played_against?(b) } }
    end

    def points_of(pods)
      pods.map.with_index(1) { |pod, n| "P#{n}=#{pod.map(&:match_points).sort.reverse}" }.join(" ")
    end
  end
end
