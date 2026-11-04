# frozen_string_literal: true

require "test_helper"

class OneVOneTiebreakersTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
  # The standings load and every tiebreaker for the whole field: a fixed count, whatever the field size.
  QUERIES = 6
  setup do
    @t = TournamentBuilder.build(players: 10, organizer: event_organizers(:standard_organizer), format: "one_v_one")
    @t.update_columns(seed: 7, swiss_rounds_count: 8, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    @p = @t.event_participants.order(:id).to_a
  end

  test "1v1 events keep 3/1/0/3 and standing columns" do
    assert_equal [3, 1, 0, 3], [@t.points_win, @t.points_draw, @t.points_loss, @t.points_bye]
    assert_equal %i[points omw gw ogw], @p.first.standing_columns.keys
  end

  test "match win rate: 5-2-1 over 8 rounds is 0.667, 1-3-0 floors at 0.33" do
    me = @p[0]
    # 5 wins, 1 draw, 2 losses (games 2-0 / 1-1 / 0-2)
    [[2, 0]].cycle.first(5).each_with_index { |s, i| play(i + 1, me, @p[1 + (i % 9)], s) }
    play(6, me, @p[2], [1, 1])
    2.times { |i| play(7 + i, me, @p[3 + i], [0, 2]) }
    me = EventParticipant.find(me.id)
    assert_equal 16, me.match_points
    assert_in_delta 16.0 / 24, me.match_win_rate, 0.0001
    assert_in_delta 0.667, me.match_win_rate, 0.001

    low = @p[9]
    play(9, low, @p[1], [2, 0])
    3.times { |i| play(10 + i, low, @p[2 + i], [0, 2]) }
    assert_in_delta 0.33, EventParticipant.find(low.id).match_win_rate, 0.0001
  end

  test "a bye counts 2-0 for the player's own rates and is excluded from OMW" do
    a = @p[0]
    b = @p[1]
    play(1, a, b, [0, 2])
    bye(2, a)
    a = EventParticipant.find(a.id)
    assert_equal 3, a.match_points
    assert_in_delta 3.0 / 6, a.match_win_rate, 0.0001
    assert_in_delta 6.0 / 12, a.game_win_rate, 0.0001 # 0 + 6 points over (2 + 2) games
    assert_in_delta 1.0, EventParticipant.find(b.id).match_win_rate, 0.0001
    assert_in_delta 1.0, a.opponents_match_win_rate, 0.0001 # only b; the bye adds nobody
  end

  test "no opponents yet gives 0.33 and floors apply to each opponent" do
    assert_in_delta 0.33, @p[0].opponents_match_win_rate, 0.0001
    assert_in_delta 0.33, @p[0].opponents_game_win_rate, 0.0001
    a, b, c = @p.first(3)
    play(1, a, b, [2, 0]) # b lost: floored 0.33
    play(2, a, c, [2, 1])
    play(3, c, @p[3], [2, 0]) # c: 1 win + 1 loss = 0.5
    a = EventParticipant.find(a.id)
    assert_in_delta (0.33 + 0.5) / 2, a.opponents_match_win_rate, 0.0001
    # b: 0 game points of 6, floored to 0.33; c: 1-2 then 2-0 = 9 game points over 5 games (9/15)
    assert_in_delta (0.33 + (9.0 / 15)) / 2, a.opponents_game_win_rate, 0.0001
  end

  test "rank_score orders by points, then OMW, then GW, then OGW" do
    a = @p[0]
    b = @p[1]
    assert_operator ranked(a, points: 4, omw: 0.4, gw: 0.4, ogw: 0.4), :>,
                    ranked(b, points: 3, omw: 0.9, gw: 0.9, ogw: 0.9)
    assert_operator ranked(a, points: 3, omw: 0.41, gw: 0.4, ogw: 0.4), :>,
                    ranked(b, points: 3, omw: 0.4, gw: 0.9, ogw: 0.9)
    assert_operator ranked(a, points: 3, omw: 0.4, gw: 0.51, ogw: 0.4), :>,
                    ranked(b, points: 3, omw: 0.4, gw: 0.5, ogw: 0.9)
    assert_operator ranked(a, points: 3, omw: 0.4, gw: 0.5, ogw: 0.51), :>,
                    ranked(b, points: 3, omw: 0.4, gw: 0.5, ogw: 0.5)
    assert_kind_of Integer, ranked(a, points: 3, omw: 0.4, gw: 0.5, ogw: 0.5)
  end

  test "play_1v1_round! feeds the standings end to end" do
    round = round_for(1)
    pod = round.pods.create!(number: 1, size: 2)
    @p.first(2).each_with_index { |ep, i| pod.seatings.create!(event_participant: ep, order: i + 1) }
    TournamentBuilder.play_1v1_round!(@t, scores: { 1 => [2, 1] })
    winner = EventParticipant.find(@p[0].id)
    assert_equal 3, winner.match_points
    assert_in_delta 6.0 / 9, winner.game_win_rate, 0.0001 # 2-1: 6 game points of 9
    assert_equal [2, 1, 0], winner.results.first.games
  end

  test "a loaded standings ranks every participant without N+1 queries" do
    play(1, @p[0], @p[1], [2, 0])
    play(2, @p[0], @p[2], [2, 1])
    play(2, @p[1], @p[3], [1, 1])
    ranked = nil
    assert_queries_count(QUERIES) do
      ranked = EventParticipant.standings_for(@t).sort_by(&:rank_score).reverse
      ranked.each(&:standing_columns)
    end
    assert_equal @p[0].id, ranked.first.id
    assert_empty ranked.last.opponent_records
    assert_in_delta 0.33, ranked.last.opponents_game_win_rate, 0.0001
  end

  test "a 1-1-1 draw is 4 game points over 3 games" do
    play(1, @p[0], @p[1], [1, 1, 1])
    a = EventParticipant.find(@p[0].id)
    assert_equal 1, a.number_of_draws
    assert_equal [1, 1, 1], a.results.first.games
    assert_in_delta 4.0 / 9, a.game_win_rate, 0.0001
    assert_in_delta 4.0 / 9, EventParticipant.find(@p[1].id).game_win_rate, 0.0001
  end

  test "a penalty in the cut does not change the swiss rounds played or the seed score" do
    play(1, @p[0], @p[1], [2, 0])
    before = EventParticipant.find(@p[0].id)
    seed = before.one_v_one_seed_score
    cut = SingleEliminationRound.new(event: @t, number: 9)
    cut.define_singleton_method(:create_pods) { nil }
    cut.save!
    Penalty.create!(round: cut, event_participant: @p[0])
    after = EventParticipant.find(@p[0].id)
    assert_equal 1, after.number_of_rounds_played
    assert_in_delta 1.0, after.match_win_rate, 0.0001
    assert_equal seed, after.one_v_one_seed_score
  end

  private

  def round_for(number)
    @t.rounds.find_by(number: number) || new_round(number)
  end

  # The multiplayer pairer seats everyone on round creation; the 1v1 pairer is not here yet, so start empty.
  def new_round(number)
    round = @t.rounds.create!(type: SwissRound, number: number)
    round.pods.destroy_all
    round
  end

  # score: [won, lost] or [won, lost, drawn] for the first player; the second gets the mirror.
  def play(number, one, two, score)
    won, lost, drawn = score
    round = round_for(number)
    pod = round.pods.create!(number: round.pods.count + 1, size: 2)
    [[one, won, lost], [two, lost, won]].each.with_index(1) do |(ep, games_won, games_lost), order|
      pod.seatings.create!(event_participant: ep, order: order)
      TournamentBuilder.record_1v1!(round, ep.id, games_won, games_lost, drawn || 0)
    end
    round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
  end

  # As Tournaments::OneVOnePairer writes it: an Advance with no seating, 2-0.
  def bye(number, participant)
    round = round_for(number)
    Advance.create!(round: round, event_participant: participant, games_won: 2)
    round.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
  end

  def ranked(participant, points:, omw:, gw:, ogw:) # rubocop:disable Naming/MethodParameterName
    participant = EventParticipant.find(participant.id)
    participant.define_singleton_method(:match_points) { points }
    participant.define_singleton_method(:opponents_match_win_rate) { omw }
    participant.define_singleton_method(:game_win_rate) { gw }
    participant.define_singleton_method(:opponents_game_win_rate) { ogw }
    participant.define_singleton_method(:tiebreak_salt) { 0 }
    participant.rank_score
  end
end
