# frozen_string_literal: true

require "test_helper"

module Leagues
  # The gaps an audit of the open-tables league found on 2026-11-25, each pinned by a test.
  class HardeningTest < ActiveSupport::TestCase
    setup do
      @organizer = event_organizers(:standard_organizer)
    end

    test "a league with no cut never makes one, however many qualify" do
      league, players = league_with(8, top_cut_size: 0, min_games_for_cut: 0)
      play(league, players.first(4), winner: players[0])
      Lifecycle.close(league, by: @organizer.user)

      assert_equal 0, league.cut_size_for_field
      Lifecycle.make_cut(league, by: @organizer.user)

      assert_predicate league.reload, :finished?
      assert_not league.rounds.exists?(type: "LeagueCutRound")
    end

    test "the starting points show before the first game and follow the organizer's change" do
      league, players = league_with(4, starting_points: 500, state: :registration_open)
      assert_equal [500], players.map { |player| player.league_score.to_i }.uniq

      league.update!(starting_points: 800)

      assert_equal [800], league.event_participants.pluck(:league_score).map(&:to_i).uniq
    end

    test "a new league stakes 10% unless the organizer says otherwise, and a blank wager is refused" do
      league = League.new(name: "Nova", event_organizer: @organizer, start_time: 1.day.from_now,
                          end_time: 1.month.from_now)
      assert_equal 10, league.wager_percentage.to_i

      league.wager_percentage = nil
      assert_not league.valid?
      assert league.errors.key?(:wager_percentage)
    end

    test "the league cannot finish with a correction waiting" do
      league, players = league_with(4, top_cut_size: 0)
      pod = play(league, players, winner: players[0])
      Lifecycle.close(league, by: @organizer.user)
      table = league.league_tables.find_by!(pod: pod)
      Tables::RequestCorrection.call(table: table, participant: players[1], reason: "Ganhei eu")

      assert_raises(Lifecycle::NotAllowed) { Lifecycle.finish(league.reload, by: @organizer.user) }

      Tables::ResolveCorrection.call(table: table, by: @organizer.user, result: "keep")
      Lifecycle.finish(league.reload, by: @organizer.user)
      assert_predicate league.reload, :finished?
    end

    test "a player answered about a game cannot ask again; another player of it can" do
      league, players = league_with(4)
      pod = play(league, players, winner: players[0])
      table = league.league_tables.find_by!(pod: pod)
      Tables::RequestCorrection.call(table: table, participant: players[1], reason: "Ganhei eu")
      Tables::ResolveCorrection.call(table: table, by: @organizer.user, result: "keep")

      error =
        assert_raises(Tables::NotAllowed) do
          Tables::RequestCorrection.call(table: table.reload, participant: players[1], reason: "Outra vez")
        end
      assert_equal "already_answered", error.message

      Tables::RequestCorrection.call(table: table.reload, participant: players[2], reason: "Foi empate")
      assert_predicate table.reload, :correction_pending?
    end

    test "the organizer cancels a full table on their own, with a reason" do
      league, players = league_with(4)
      pod = LeagueBuilder.fill_table!(league, players)
      table = league.league_tables.find_by!(pod: pod)

      assert_raises(Tables::NotAllowed) { Tables::DecideCancel.void(table: table, by: @organizer.user, reason: " ") }
      Tables::DecideCancel.void(table: table, by: @organizer.user, reason: "Os jogadores desapareceram")

      assert_predicate table.reload, :cancelled?
      assert_equal "Os jogadores desapareceram", table.cancel_reason
      assert_equal 0, league.rounds.count
      assert_not LeagueTableSeat.active.exists?(league_table_id: table.id)
    end

    test "closing the league leaves alone a table that filled meanwhile" do
      league, players = league_with(8)
      waiting = Tables::Open.call(league: league, participant: players[4])
      LeagueBuilder.fill_table!(league, players.first(4))

      Lifecycle.close(league, by: @organizer.user)

      assert_predicate waiting.reload, :closed?
      assert_predicate league.reload, :closing?
      assert_equal 1, league.league_tables.filled.count
    end

    test "a finished league reads in its final order" do
      league, players = league_with(8, min_games_for_cut: 0, top_cut_size: 4)
      play(league, players.first(4), winner: players[0])
      Lifecycle.close(league, by: @organizer.user)
      Lifecycle.make_cut(league, by: @organizer.user)
      final = league.rounds.find_by!(type: "LeagueCutRound")
      final.update!(published: true, started_at: Time.current)
      champion = final.pods.sole.seatings.max_by(&:order).event_participant
      Results::Apply.call(pod: final.pods.sole, type: "Win", winner: champion)
      final.update!(finished_at: Time.current)

      assert_predicate league.reload, :finished?
      assert_equal 1, champion.reload.final_position
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
      pod
    end
  end
end
