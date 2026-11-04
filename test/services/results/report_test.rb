# frozen_string_literal: true

require "test_helper"

module Results
  class ReportTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
    setup do
      @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      @pod = @t.rounds.create!(type: SwissRound, number: 1, started_at: 1.hour.ago).pods.first
      @seats = @pod.event_participants.to_a
    end

    test "none applies at once and records who reported" do
      @t.update!(result_confirmation: "none")

      Report.call(pod: @pod, participant: @seats[1], type: "Win", winner: @seats[1])

      @pod.reload
      assert_predicate @pod, :finished?
      assert_equal :completed, @pod.report_status
      assert_equal %w[Win], Result.current.where(event_participant: @seats[1]).pluck(:type)
      assert_equal @seats[1].id, @pod.reported_by_participant_id
      assert_not_nil @pod.reported_at
      assert_nil @pod.pending_result
      assert_empty @pod.confirmations
    end

    test "one leaves the result pending with the reporter's confirmation" do
      @t.update!(result_confirmation: "one")

      Report.call(pod: @pod, participant: @seats[0], type: "Win", winner: @seats[2])

      @pod.reload
      assert_equal :pending, @pod.report_status
      assert_equal({ "type" => "Win", "winner_id" => @seats[2].id }, @pod.pending_result)
      assert_equal [@seats[0].id], @pod.confirmations.keys
      assert_equal @seats[0].id, @pod.reported_by_participant_id
      assert_empty @pod.results
    end

    test "a draw is stored without a winner" do
      @t.update!(result_confirmation: "all")

      Report.call(pod: @pod, participant: @seats[0], type: "Draw")

      assert_equal({ "type" => "Draw" }, @pod.reload.pending_result)
    end

    test "the same report from a second player counts as a confirmation" do
      @t.update!(result_confirmation: "one")
      Report.call(pod: @pod, participant: @seats[0], type: "Win", winner: @seats[2])

      Report.call(pod: @pod, participant: @seats[3], type: "Win", winner: @seats[2])

      @pod.reload
      assert_equal :completed, @pod.report_status
      assert_equal 2, @pod.confirmations.size
      assert_equal %w[Win], Result.current.where(event_participant: @seats[2]).pluck(:type)
    end

    test "a different report while pending disputes the pod and calls a judge" do
      @t.update!(result_confirmation: "one")
      Report.call(pod: @pod, participant: @seats[0], type: "Win", winner: @seats[2])

      assert_difference -> { JudgeCall.where(pod: @pod).count }, 1 do
        Report.call(pod: @pod, participant: @seats[3], type: "Draw")
      end

      @pod.reload
      assert_equal :disputed, @pod.report_status
      assert_empty @pod.results
      call = JudgeCall.find_by(pod: @pod)
      seat = ->(p) { @pod.seatings.find_by(event_participant: p).order }
      assert_equal "Conflicting result reports: seat #{seat.call(@seats[0])} says Win by #{@seats[2].name}; " \
                   "seat #{seat.call(@seats[3])} says Draw", call.reason
      assert_equal @seats[3], call.participant
    end

    test "a dispute on a table with an open call adds to that call" do
      @t.update!(result_confirmation: "one")
      call = JudgeCalls::Open.call(event: @t, pod: @pod, participant: @seats[1], reason: "Rules question")
      Report.call(pod: @pod, participant: @seats[0], type: "Win", winner: @seats[2])

      assert_no_difference -> { JudgeCall.count } do
        Report.call(pod: @pod, participant: @seats[3], type: "Draw")
      end

      assert_predicate @pod.reload, :disputed?
      assert_match(/\ARules question\nConflicting result reports: /, call.reload.reason)
    end

    test "a report before the round has started is refused" do
      @t.update!(result_confirmation: "none")
      @pod.round.update!(started_at: nil)

      error = assert_raises(NotAllowed) { Report.call(pod: @pod, participant: @seats[0], type: "Draw") }
      assert_equal "round_not_started", error.message
      assert_empty @pod.reload.results
      assert_nil @pod.pending_result
    end

    test "self-reporting disabled is refused" do
      @t.update!(self_report_enabled: false)

      error = assert_raises(NotAllowed) { Report.call(pod: @pod, participant: @seats[0], type: "Draw") }
      assert_equal "self_report_disabled", error.message
    end

    test "a player from another pod is refused" do
      outsider = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
        .event_participants.first

      assert_raises(NotAllowed) { Report.call(pod: @pod, participant: outsider, type: "Draw") }
    end

    test "a finished pod is refused" do
      Apply.call(pod: @pod, type: "Draw")

      error = assert_raises(NotAllowed) { Report.call(pod: @pod, participant: @seats[0], type: "Draw") }
      assert_equal "already_finished", error.message
    end

    test "only Win and Draw, and a win needs a winner from the pod" do
      outsider = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
        .event_participants.first

      assert_raises(NotAllowed) { Report.call(pod: @pod, participant: @seats[0], type: "Penalty", winner: @seats[0]) }
      assert_raises(NotAllowed) { Report.call(pod: @pod, participant: @seats[0], type: "Win") }
      assert_raises(NotAllowed) { Report.call(pod: @pod, participant: @seats[0], type: "Win", winner: outsider) }
      assert_empty @pod.reload.results
    end

    test "a report on a disputed pod is refused" do
      @t.update!(result_confirmation: "one")
      Report.call(pod: @pod, participant: @seats[0], type: "Draw")
      Report.call(pod: @pod, participant: @seats[1], type: "Win", winner: @seats[1])

      error = assert_raises(NotAllowed) { Report.call(pod: @pod, participant: @seats[2], type: "Draw") }
      assert_equal "disputed", error.message
      assert_equal 1, JudgeCall.where(pod: @pod).count
    end

    test "a player who already confirmed cannot report again" do
      @t.update!(result_confirmation: "all")
      Report.call(pod: @pod, participant: @seats[0], type: "Draw")

      error =
        assert_raises(NotAllowed) do
          Report.call(pod: @pod, participant: @seats[0], type: "Win", winner: @seats[0])
        end
      assert_equal "already_confirmed", error.message
      assert_not @pod.reload.disputed?
    end
  end
end
