# frozen_string_literal: true

require "test_helper"

module Leagues
  class CutTest < ActiveSupport::TestCase
    setup do
      @organizer = event_organizers(:standard_organizer)
    end

    test "only players with the minimum games qualify, in standings order" do
      league, players = league_with(8, min_games_for_cut: 1)
      play(league, players.first(4), winner: players[2])

      assert_equal [players[2], players[0], players[1], players[3]].map(&:id), league.cut_field.map(&:id)

      league.update!(min_games_for_cut: 0)
      assert_equal 8, league.cut_field.size
      assert_equal players[2].id, league.cut_field.first.id
    end

    test "twenty qualified players make a top 16 in four pods, then a final, and the league finishes" do
      league, players = league_with(20, min_games_for_cut: 1)
      players.each_slice(4) { |four| play(league, four, winner: four[0]) }
      Lifecycle.close(league, by: @organizer.user)
      scores = players.map { |player| player.reload.league_score }

      Lifecycle.make_cut(league, by: @organizer.user)

      assert_predicate league.reload, :finals?
      semis = league.rounds.find_by!(type: "LeagueCutRound")
      assert_equal "Top 16", semis.display_name
      assert_equal 4, semis.pods.count
      assert_equal 16, semis.seatings.count
      assert_equal 4, Eliminated.where(round: semis).count
      winners = players.each_slice(4).map(&:first)
      assert(winners.first(4).all? { |winner| semis.seatings.exists?(event_participant: winner) })

      finalists = close_round(semis)
      final = league.rounds.where(type: "LeagueCutRound").order(:number).last
      assert_equal "Finals", final.display_name
      assert_equal finalists.map(&:id).sort, final.seatings.pluck(:event_participant_id).sort

      champion = close_round(final).first

      assert_predicate league.reload, :finished?
      assert_equal 1, champion.reload.final_position
      assert_equal (1..20).to_a, league.event_participants.pluck(:final_position).sort
      assert_equal [2, 3, 4], (finalists - [champion]).map { |p| p.reload.final_position }.sort
      assert_equal(scores, players.map { |player| player.reload.league_score })
    end

    test "nine qualified players with a cut of 16 play a top 4" do
      league, players = league_with(12, min_games_for_cut: 1)
      players.first(8).each_slice(4) { |four| play(league, four, winner: four[0]) }
      play(league, [players[8], *players[0, 3]], winner: players[8])
      Lifecycle.close(league, by: @organizer.user)

      Lifecycle.make_cut(league, by: @organizer.user)

      assert_equal 4, league.reload.top_cut_size
      final = league.rounds.find_by!(type: "LeagueCutRound")
      assert_equal "Finals", final.display_name
      assert_equal 4, final.seatings.count
    end

    test "with too few qualified players the league finishes by the standings" do
      league, players = league_with(6, min_games_for_cut: 2)
      play(league, players.first(4), winner: players[1])
      Lifecycle.close(league, by: @organizer.user)

      Lifecycle.make_cut(league, by: @organizer.user)

      assert_predicate league.reload, :finished?
      assert_equal 1, players[1].reload.final_position
      assert_equal (1..6).to_a, league.event_participants.pluck(:final_position).sort
    end

    test "the cut cannot be made while the league is still in play" do
      league, = league_with(4)

      assert_raises(Lifecycle::NotAllowed) { Lifecycle.make_cut(league, by: @organizer.user) }
    end

    private

    def league_with(count, **settings)
      league = LeagueBuilder.build(players: count, organizer: @organizer, **settings)
      [league, league.event_participants.order(:created_at).to_a]
    end

    def play(league, players, winner:)
      pod = LeagueBuilder.fill_table!(league, players)
      Results::Apply.call(pod: pod, type: "Win", winner: winner)
      travel 1.minute
    end

    # The first seat of every pod wins and the round is closed, as the organizer does. Returns the winners.
    def close_round(round)
      round.update!(published: true, started_at: Time.current)
      winners =
        round.pods.order(:number).map do |pod|
          winner = pod.seatings.min_by(&:order).event_participant
          Results::Apply.call(pod: pod, type: "Win", winner: winner)
          winner
        end
      round.update!(finished_at: Time.current)
      winners
    end
  end
end
