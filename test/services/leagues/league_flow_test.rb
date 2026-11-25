# frozen_string_literal: true

require "test_helper"

module Leagues
  # The 24-hour acceptance, the stale-table notice, cancelling a table and closing / reopening the league.
  class LeagueFlowTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    setup do
      @organizer = event_organizers(:standard_organizer)
      @league = LeagueBuilder.build(players: 8, organizer: @organizer)
      @players = @league.event_participants.order(:created_at).to_a
      @pod = LeagueBuilder.fill_table!(@league, @players.first(4))
      @table = @pod.league_table
    end

    test "a report nobody contested for 24 hours is accepted and scored" do
      Results::Report.call(pod: @pod, participant: @players[0], type: "Win", winner: @players[0])
      @pod.update_column(:reported_at, 23.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      AcceptPendingJob.perform_now
      assert_equal 1000, @players[0].reload.league_score.to_i

      @pod.update_column(:reported_at, 25.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      AcceptPendingJob.perform_now

      assert_equal([1300, 900, 900, 900], @players.first(4).map { |p| p.reload.league_score.to_i })
      assert_nil @pod.reload.pending_result
    end

    test "a contested report is never accepted by itself" do
      Results::Report.call(pod: @pod, participant: @players[0], type: "Win", winner: @players[0])
      Results::Contest.call(pod: @pod, participant: @players[1], reason: "I won")
      @pod.update_column(:reported_at, 3.days.ago) # rubocop:disable Rails/SkipsModelValidations

      AcceptPendingJob.perform_now

      assert_not @pod.reload.finished?
    end

    test "a league's pending report is not sent to staff review like a tournament's" do
      Results::Report.call(pod: @pod, participant: @players[0], type: "Win", winner: @players[0])
      @pod.update_column(:reported_at, 2.days.ago) # rubocop:disable Rails/SkipsModelValidations

      Results::ExpirePendingJob.perform_now

      assert_nil @pod.reload.review_requested_at
    end

    test "a table full for a week with no result notifies the staff once" do
      @table.update_column(:filled_at, 8.days.ago) # rubocop:disable Rails/SkipsModelValidations

      assert_difference -> { Notification.where(kind: "league_table_stale", user: @organizer.user).count }, 1 do
        2.times { FlagStaleTablesJob.perform_now }
      end
    end

    test "a cancellation needs a reason and a player of the table" do
      assert_equal("reason_required", refused { request_cancel(@players[0], "  ") })
      assert_equal("not_member", refused { request_cancel(@players[5], "No show") })
    end

    test "a request keeps the four at the table and tells the staff" do
      assert_difference -> { Notification.where(kind: "league_cancel_requested").count }, 1 do
        request_cancel(@players[2], "Player 4 never showed up")
      end

      assert_predicate @table.reload, :cancel_pending?
      assert_equal("already_requested", refused { request_cancel(@players[0], "Again") })
      assert_equal("busy", refused { Tables::Open.call(league: @league, participant: @players[0]) })
    end

    test "approving removes the game, frees the four and leaves the scores alone" do
      other = LeagueBuilder.fill_table!(@league, @players.last(4))
      Results::Apply.call(pod: other, type: "Win", winner: @players[4])
      request_cancel(@players[0], "Agreed to cancel")

      Tables::DecideCancel.call(table: @table, by: @organizer.user, approve: true)

      assert_predicate @table.reload, :cancelled?
      assert_nil @table.pod
      assert_not Pod.exists?(@pod.id)
      assert_equal([1000, 1000, 1000, 1000, 1300], @players.first(5).map { |p| p.reload.league_score.to_i })
      assert Tables::Open.call(league: @league, participant: @players[0])
      assert AuditEvent.exists?(action: "league_table_cancel_decided", subject: @table)
    end

    test "refusing keeps the table to be reported" do
      request_cancel(@players[0], "Please")

      Tables::DecideCancel.call(table: @table, by: @organizer.user, approve: false)

      assert_predicate @table.reload, :filled?
      assert_equal "refused", @table.cancel_state
      assert Pod.exists?(@pod.id)
      assert_equal("nothing_pending", refused do
        Tables::DecideCancel.call(table: @table, by: @organizer.user, approve: true)
      end)
    end

    test "an accepted result answers a pending request" do
      request_cancel(@players[0], "Please")

      Results::Apply.call(pod: @pod, type: "Win", winner: @players[1])

      assert_equal "refused", @table.reload.cancel_state
    end

    test "closing voids waiting tables, lets the full ones finish and then closes the league" do
      waiting = Tables::Open.call(league: @league, participant: @players[4])

      Lifecycle.close(@league, by: @organizer.user)

      assert_predicate @league.reload, :closing?
      assert_predicate waiting.reload, :closed?
      assert_equal("closed", refused { Tables::Open.call(league: @league, participant: @players[5]) })

      Results::Apply.call(pod: @pod, type: "Win", winner: @players[0])

      assert_predicate @league.reload, :closed?
    end

    test "a closing league closes when its last table is cancelled" do
      Lifecycle.close(@league, by: @organizer.user)
      request_cancel(@players[0], "Cannot play any more")

      Tables::DecideCancel.call(table: @table, by: @organizer.user, approve: true)

      assert_predicate @league.reload, :closed?
    end

    test "closing with nothing in play closes at once" do
      Results::Apply.call(pod: @pod, type: "Draw")

      Lifecycle.close(@league, by: @organizer.user)

      assert_predicate @league.reload, :closed?
    end

    test "a closed league reopens to play until the cut starts" do
      Results::Apply.call(pod: @pod, type: "Draw")
      Lifecycle.close(@league, by: @organizer.user)

      Lifecycle.reopen(@league, by: @organizer.user)

      assert_predicate @league.reload, :play?
      assert Tables::Open.call(league: @league, participant: @players[0])

      Lifecycle.close(@league, by: @organizer.user)
      LeagueCutRound.insert({ event_id: @league.id, number: 99, created_at: Time.current, updated_at: Time.current }) # rubocop:disable Rails/SkipsModelValidations
      assert_equal "cut_started", assert_raises(Lifecycle::NotAllowed) {
        Lifecycle.reopen(@league, by: @organizer.user)
      }.message
    end

    test "starting moves a league with registration open into play" do
      league = LeagueBuilder.build(players: 4, organizer: @organizer, state: :registration_open)

      Lifecycle.start(league, by: @organizer.user)

      assert_predicate league.reload, :tables_open?
    end

    private

    def request_cancel(participant, reason)
      Tables::RequestCancel.call(table: @table, participant: participant, reason: reason)
    end

    def refused(&block) = assert_raises(Tables::NotAllowed, &block).message
  end
end
