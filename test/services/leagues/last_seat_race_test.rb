# frozen_string_literal: true

require "test_helper"

module Leagues
  # Two players ask for the last seat of a table at the same moment: one sits, the other is told it is full.
  # Real threads on real connections, so no wrapping transaction; the test removes what it created.
  class LastSeatRaceTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @started = Time.current
      @league = LeagueBuilder.build(players: 5, organizer: event_organizers(:standard_organizer))
      @players = @league.event_participants.order(:created_at).to_a
      @table = Tables::Open.call(league: @league, participant: @players[0])
      @players[1..2].each { |participant| Tables::Join.call(table: @table, participant: participant) }
    end

    teardown do
      players = Player.where(id: @players.map(&:player_id))
      [Notification, AuditEvent].each { |model| model.where(created_at: @started..).delete_all }
      @league.reload.destroy!
      players.find_each(&:destroy!)
      [Notification, AuditEvent].each { |model| model.where(created_at: @started..).delete_all }
    end

    test "the last seat goes to one of two simultaneous joins" do
      gate = Concurrent::CountDownLatch.new(1)
      outcomes =
        @players[3..4].map do |participant|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              gate.wait
              Tables::Join.call(table: LeagueTable.find(@table.id), participant: EventParticipant.find(participant.id))
              :seated
            rescue Tables::NotAllowed => e
              e.message
            end
          end
        end
      gate.count_down
      outcomes = outcomes.map(&:value)

      assert_equal 1, outcomes.count(:seated), outcomes.inspect
      assert_equal 1, (outcomes & %w[full not_waiting]).size, outcomes.inspect
      assert_predicate @table.reload, :filled?
      assert_equal League::TABLE_SIZE, @table.seats.count
      assert_equal League::TABLE_SIZE, @table.pod.seatings.count
    end
  end
end
