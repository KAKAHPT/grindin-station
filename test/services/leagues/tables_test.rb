# frozen_string_literal: true

require "test_helper"

module Leagues
  class TablesTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    setup do
      @league = LeagueBuilder.build(players: 9, organizer: event_organizers(:standard_organizer))
      @players = @league.event_participants.order(:created_at).to_a
    end

    test "opening a table seats the opener and waits" do
      table = Tables::Open.call(league: @league, participant: @players[0])

      assert_predicate table, :waiting?
      assert_equal [@players[0]], table.participants.to_a
      assert_equal 0, @league.rounds.count
    end

    test "a second table while seated is refused" do
      Tables::Open.call(league: @league, participant: @players[0])

      error = assert_raises(Tables::NotAllowed) { Tables::Open.call(league: @league, participant: @players[0]) }
      assert_equal "busy", error.message
    end

    test "a third player keeps the table waiting" do
      table = Tables::Open.call(league: @league, participant: @players[0])
      Tables::Join.call(table: table, participant: @players[1])
      Tables::Join.call(table: table, participant: @players[2])

      assert_predicate table.reload, :waiting?
      assert_nil table.pod
    end

    test "the fourth player fills the table: one game round, one pod, four seats, four notices" do
      users = @players.first(4).map { |participant| give_account(participant) }

      pod = LeagueBuilder.fill_table!(@league, @players.first(4))

      table = @league.league_tables.sole
      assert_predicate table, :filled?
      assert_not_nil table.filled_at
      round = @league.rounds.sole
      assert_instance_of LeagueGameRound, round
      assert round.published? && round.started? && round.is_play_round?
      assert_equal [pod], round.pods.to_a
      assert_equal [1, 2, 3, 4], pod.seatings.map(&:order)
      assert_equal @players.first(4).map(&:id).sort, pod.seatings.map(&:event_participant_id).sort
      assert_equal users.map(&:id).sort,
                   Notification.where(kind: "league_table_full", subject: pod).pluck(:user_id).sort
    end

    test "a fifth player is refused" do
      LeagueBuilder.fill_table!(@league, @players.first(4))

      error =
        assert_raises(Tables::NotAllowed) do
          Tables::Join.call(table: @league.league_tables.sole, participant: @players[4])
        end
      assert_equal "not_waiting", error.message
    end

    test "a player at a full table cannot open or join another until it is settled" do
      LeagueBuilder.fill_table!(@league, @players.first(4))
      other = Tables::Open.call(league: @league, participant: @players[4])

      assert_equal "busy", assert_raises(Tables::NotAllowed) {
        Tables::Join.call(table: other, participant: @players[0])
      }.message
    end

    test "two games get consecutive round numbers" do
      LeagueBuilder.fill_table!(@league, @players[0, 4])
      LeagueBuilder.fill_table!(@league, @players[4, 4])

      assert_equal [1, 2], @league.rounds.order(:number).pluck(:number)
    end

    test "leaving frees the player and keeps the table" do
      table = Tables::Open.call(league: @league, participant: @players[0])
      Tables::Join.call(table: table, participant: @players[1])

      Tables::Leave.call(table: table, participant: @players[1])

      assert_equal [@players[0]], table.reload.participants.to_a
      assert Tables::Open.call(league: @league, participant: @players[1])
    end

    test "the opener cannot leave, only close" do
      table = Tables::Open.call(league: @league, participant: @players[0])

      assert_equal "opener_closes", assert_raises(Tables::NotAllowed) {
        Tables::Leave.call(table: table, participant: @players[0])
      }.message
    end

    test "only the opener closes the table, and that frees everyone" do
      table = Tables::Open.call(league: @league, participant: @players[0])
      Tables::Join.call(table: table, participant: @players[1])

      assert_equal "not_opener", assert_raises(Tables::NotAllowed) {
        Tables::Close.call(table: table, participant: @players[1])
      }.message

      Tables::Close.call(table: table, participant: @players[0])

      assert_predicate table.reload, :closed?
      assert Tables::Open.call(league: @league, participant: @players[1])
      assert Tables::Open.call(league: @league, participant: @players[0])
    end

    test "a table open for two hours expires, a younger one stays" do
      old = Tables::Open.call(league: @league, participant: @players[0])
      Tables::Join.call(table: old, participant: @players[1])
      young = Tables::Open.call(league: @league, participant: @players[2])
      old.update_column(:created_at, 121.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      young.update_column(:created_at, 119.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      assert_equal 1, Tables::Expire.call

      assert_predicate old.reload, :expired?
      assert_predicate young.reload, :waiting?
      assert Tables::Open.call(league: @league, participant: @players[1])
    end

    test "an overdue table cannot be joined even before the job ran" do
      table = Tables::Open.call(league: @league, participant: @players[0])
      table.update_column(:created_at, 3.hours.ago) # rubocop:disable Rails/SkipsModelValidations

      assert_equal "not_waiting", assert_raises(Tables::NotAllowed) {
        Tables::Join.call(table: table, participant: @players[1])
      }.message
    end

    test "the weekly limit refuses one game too many" do
      @league.update!(max_games_per_week: 1)
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))
      pod.league_table.release_seats!

      assert_equal "limit_week", assert_raises(Tables::NotAllowed) {
        Tables::Open.call(league: @league, participant: @players[0])
      }.message
    end

    test "the same-opponent limit refuses joining a table with someone already played that often" do
      @league.update!(max_games_vs_same_opponent: 1)
      pod = LeagueBuilder.fill_table!(@league, @players.first(4))
      pod.league_table.release_seats!
      table = Tables::Open.call(league: @league, participant: @players[0])

      assert_equal "limit_opponent", assert_raises(Tables::NotAllowed) {
        Tables::Join.call(table: table, participant: @players[1])
      }.message
      assert Tables::Join.call(table: table, participant: @players[4])
    end

    test "no table opens when the league is not in play, past its end date, or for an outsider" do
      outsider = LeagueBuilder.build(players: 1,
                                     organizer: event_organizers(:standard_organizer)).event_participants.sole
      assert_equal "not_enrolled", assert_raises(Tables::NotAllowed) {
        Tables::Open.call(league: @league, participant: outsider)
      }.message

      @league.update_column(:end_time, 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
      assert_equal "closed", assert_raises(Tables::NotAllowed) {
        Tables::Open.call(league: @league, participant: @players[0])
      }.message

      @league.update_columns(end_time: 1.day.from_now, state: League.states[:registration_open]) # rubocop:disable Rails/SkipsModelValidations
      assert_equal "closed", assert_raises(Tables::NotAllowed) {
        Tables::Open.call(league: @league, participant: @players[0])
      }.message
    end

    test "seats follow the fair order: whoever sat first least often sits first" do
      first = LeagueBuilder.fill_table!(@league, @players.first(4))
      first.league_table.release_seats!
      opener = first.seatings.find_by(order: 1).event_participant

      second = LeagueBuilder.fill_table!(@league, [opener, *@players[4, 3]])

      assert_not_equal opener.id, second.seatings.find_by(order: 1).event_participant_id
    end

    private

    def give_account(participant)
      user = User.create!(name: participant.name, email_address: "conta-#{SecureRandom.hex(4)}@example.com",
                          password: "password123", confirmed_at: Time.current)
      participant.player.update!(user: user)
      user
    end
  end
end
