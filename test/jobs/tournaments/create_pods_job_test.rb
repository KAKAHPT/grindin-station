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

    # With 16 players, round 3 is left out: the greedy RematchRepair sometimes leaves 2–4 rematches there (swiss too).
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

    test "byes, 13 players: three pods of 4 and a bye for the lowest ranked player" do
      t = uneven_tournament(13, "byes")
      round = t.rounds.create!(type: SwissRound, number: 1)
      assert_equal [4, 4, 4], round.pods.order(:number).map(&:size)
      byes = round.all_results.where(type: "Advance").to_a
      assert_equal 1, byes.size
      assert_equal PlayerSorter.new(round).sorted_players.last.id, byes.first.event_participant_id
      assert_equal 12, round.seatings.count
      assert_not_includes round.seatings.map(&:event_participant_id), byes.first.event_participant_id

      round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
      bye = EventParticipant.find(byes.first.event_participant_id)
      assert_equal 1, bye.number_of_byes
      assert_equal t.points_bye, bye.match_points
    end

    test "byes, 14 players: three pods of 4 and two byes" do
      round = uneven_tournament(14, "byes").rounds.create!(type: SwissRound, number: 1)
      assert_equal [4, 4, 4], round.pods.order(:number).map(&:size)
      assert_equal 2, round.all_results.where(type: "Advance").count
      assert_equal 12, round.seatings.count
    end

    test "pods of three, 5 players: one pod of 4 and a bye" do
      round = uneven_tournament(5, "pods_of_three").rounds.create!(type: SwissRound, number: 1)
      assert_equal [4], round.pods.order(:number).map(&:size)
      assert_equal 1, round.all_results.where(type: "Advance").count
      assert_equal 4, round.seatings.count
    end

    test "a round already paired is not paired again" do
      t = uneven_tournament(13, "byes")
      round = t.rounds.create!(type: SwissRound, number: 1)
      assert_raises(ArgumentError) { CreatePodsJob.perform_now(round) }

      round.pods.destroy_all # the bye result alone still marks the round as paired
      assert_raises(ArgumentError) { CreatePodsJob.perform_now(round.reload) }
      assert_equal 1, round.all_results.where(type: "Advance").count
    end

    # A bye worth a draw: after an all-draw round 1 everybody has 1 point, and the round 1 bye (no opponents yet)
    # ranks last, so only the short count keeps them from a second bye.
    test "byes, 13 players, bye worth a draw: the round 1 bye is not the round 2 bye" do
      t = uneven_tournament(13, "byes")
      t.update_columns(points_bye: 1) # rubocop:disable Rails/SkipsModelValidations -- locked after the swiss starts
      assert_second_bye_skips_first(t)
    end

    test "byes, 13 players, bye worth nothing: the round 1 bye ranks last and is still skipped" do
      t = uneven_tournament(13, "byes")
      t.update_columns(points_bye: 0) # rubocop:disable Rails/SkipsModelValidations -- locked after the swiss starts
      assert_second_bye_skips_first(t)
    end

    # Round 1 [4,4,4,3], all draws; two players of pod 1 drop, so round 2 is 13 players with one bye. The pod of 3
    # players met fewer opponents and rank last on equal points; their pod of 3 counts as a short round.
    test "byes, 15 players: the round 2 bye skips the round 1 pod of 3" do
      t = uneven_tournament(15, "byes")
      r1 = t.rounds.create!(type: SwissRound, number: 1)
      assert_equal [4, 4, 4, 3], r1.pods.order(:number).map(&:size)
      small = r1.pods.find_by!(number: 4).event_participants.map(&:id)
      TournamentBuilder.play_round!(t, winners: (1..4).index_with(:draw))
      r1.pods.find_by!(number: 1).event_participants.first(2).each { |participant| participant.update!(dropped: true) }

      r2 = t.rounds.create!(type: SwissRound, number: 2)
      assert_equal [4, 4, 4], r2.pods.order(:number).map(&:size)
      bye = r2.all_results.find_by!(type: "Advance").event_participant_id
      assert_equal 3, small.size
      assert_not_includes small, bye
      assert_includes small, PlayerSorter.new(r2).sorted_players.last.id # the rule had to skip someone
    end

    # Round 1 [4,4,3,3,3] seats nine players in pods of 3 and eight in two pods of 4, all draws. Round 2 has nine seats
    # in pods of 3 and only eight players who were not short; each pod of 3 takes at most two of them without a
    # rematch, so three repeats is the floor. The pairing alone leaves 4-5; the greedy pass reaches 3-4 depending on
    # the ids, so the test checks what it guarantees: no swap of a repeating player with a non-short pod-of-4 player
    # is left that keeps the rematch count, and no rematch at all.
    test "pods of three, 17 players: round 2 leaves no swap that would stop a pod-of-3 repeat" do
      seed = 0
      4.times do
        t = TournamentBuilder.build(players: 17, organizer: event_organizers(:standard_organizer))
        seed = distinct_salt_seed(t, seed + 1) # a later seed each time, so the four tournaments differ
        t.update_columns(uneven_field: "pods_of_three", seed: seed, swiss_rounds_count: 4) # rubocop:disable Rails/SkipsModelValidations
        r1 = t.rounds.create!(type: SwissRound, number: 1)
        assert_equal [4, 4, 3, 3, 3], r1.pods.order(:number).map(&:size)
        short = r1.pods.where(size: 3).flat_map { |pod| pod.event_participants.map(&:id) }.to_set
        TournamentBuilder.play_round!(t, winners: (1..5).index_with(:draw))

        r2 = t.rounds.create!(type: SwissRound, number: 2)
        small, large =
          r2.pods.order(:number).partition { |pod| pod.size == 3 }
            .map { |pods| pods.map { |pod| pod.event_participants.to_a } }
        assert_operator small.flatten.count { |p| short.include?(p.id) }, :<=, 4, "seed #{seed}"
        assert_equal 0, rematches(r2), "seed #{seed}"
        assert_empty open_short_swaps(small, large, short), "seed #{seed}"
      end
    end

    test "the short-pod ladder stops at one win in swiss and power, any gap in random" do
      t = uneven_tournament(17, "pods_of_three")
      round = t.rounds.create!(type: SwissRound, number: 1)
      { "swiss" => [0, 1, 7], "power" => [0, 1, 7], "random" => [Float::INFINITY] }.each do |mode, gaps|
        t.update_columns(pairing_mode: mode) # rubocop:disable Rails/SkipsModelValidations -- locked after swiss
        job = CreatePodsJob.new
        job.instance_variable_set(:@round, round.reload)
        assert_equal gaps, job.send(:short_pod_gaps), mode
      end
    end

    test "byes, 16 players: no pods of 3, no byes, the short-pod pass changes nothing" do
      round = uneven_tournament(16, "byes").rounds.create!(type: SwissRound, number: 1)
      assert_equal [4, 4, 4, 4], round.pods.order(:number).map(&:size)
      assert_equal 0, round.all_results.where(type: "Advance").count
      assert_equal 16, round.seatings.count
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

    # The first seed (from `from`) whose tiebreak salts are all distinct (see EventParticipant#tiebreak_salt), so the
    # ranking, the shuffle order and the bye are deterministic.
    def distinct_salt_seed(tournament, from = 1)
      ids = tournament.event_participants.map(&:id)
      (from..).find { |s| ids.map { |id| Digest::MD5.hexdigest("#{s}-#{id}").to_i(16) % 10_000 }.uniq.size == ids.size }
    end

    def uneven_tournament(players, mode)
      t = TournamentBuilder.build(players: players, organizer: event_organizers(:standard_organizer))
      t.update_columns(uneven_field: mode, seed: distinct_salt_seed(t)) # rubocop:disable Rails/SkipsModelValidations -- locked after the swiss starts
      t
    end

    # Round 1 all draws, then round 2: the round 1 bye does not get the round 2 bye although they rank last.
    def assert_second_bye_skips_first(tournament)
      r1 = tournament.rounds.create!(type: SwissRound, number: 1)
      first_bye = bye_of(r1)
      TournamentBuilder.play_round!(tournament, winners: { 1 => :draw, 2 => :draw, 3 => :draw })
      r2 = tournament.rounds.create!(type: SwissRound, number: 2)
      assert_equal first_bye, PlayerSorter.new(r2).sorted_players.last.id
      assert_not_equal first_bye, bye_of(r2)
    end

    def bye_of(round) = round.all_results.find_by!(type: "Advance").event_participant_id

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

    # [repeater, partner] swaps between a pod of 3 and a pod of 4 that add no rematch (from a rematch-free round).
    def open_short_swaps(small, large, short)
      small.product(large).flat_map do |pod, other_pod|
        repeaters = pod.select { |p| short.include?(p.id) }
        partners = other_pod.reject { |q| short.include?(q.id) }
        repeaters.product(partners).select do |p, q|
          clean_after_swap?(pod - [p], q) && clean_after_swap?(other_pod - [q], p)
        end
      end
    end

    def clean_after_swap?(rest, newcomer) = rest.none? { |x| x.played_against?(newcomer) }

    def pod_ids(round) = round.pods.order(:number).map { |pod| pod.event_participants.map(&:id).sort }

    def rematches(round)
      round.pods.sum { |pod| pod.event_participants.to_a.combination(2).count { |a, b| a.played_against?(b) } }
    end

    def points_of(pods)
      pods.map.with_index(1) { |pod, n| "P#{n}=#{pod.map(&:match_points).sort.reverse}" }.join(" ")
    end
  end
end
