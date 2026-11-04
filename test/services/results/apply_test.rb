# frozen_string_literal: true

require "test_helper"

module Results
  class ApplyTest < ActiveSupport::TestCase
    setup do
      @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      @round = @t.rounds.create!(type: SwissRound, number: 1)
      @pod = @round.pods.first
      @seats = @pod.seatings.map(&:event_participant)
      @user = users(:organizer_user)
    end

    test "an open round is updated in place and records who entered it" do
      Apply.call(pod: @pod, type: "Win", winner: @seats[0], by: @user)
      ids = Result.where(round: @round).order(:id).pluck(:id)

      outcome = Apply.call(pod: @pod, type: "Draw", by: @user)

      assert_equal ids, Result.where(round: @round).order(:id).pluck(:id)
      assert_equal %w[Draw] * 4, Result.where(round: @round).pluck(:type)
      assert_equal [@user.id], Result.where(round: @round).distinct.pluck(:recorded_by_user_id)
      assert_nil outcome.warning
      assert_equal 4, outcome.results.size
    end

    test "a closed round gets fresh results and the old ones are superseded" do
      TournamentBuilder.play_round!(@t, winners: { 1 => 0 })
      old = Result.where(round: @round).to_a

      outcome = Apply.call(pod: @pod, type: "Win", winner: @seats[1], by: @user)

      assert_equal 8, Result.where(round: @round).count
      assert_equal 4, Result.current.where(round: @round).count
      new_by_participant = outcome.results.index_by(&:event_participant_id)
      old.each do |result|
        assert_equal new_by_participant[result.event_participant_id].id, result.reload.superseded_by_id
      end
      assert_equal [@user.id], outcome.results.map(&:recorded_by_user_id).uniq
      assert_equal @t.points_win, fresh(@seats[1]).match_points
      assert_equal @t.points_loss, fresh(@seats[0]).match_points
      assert_equal 1, fresh(@seats[0]).results.count
      assert_equal 0, fresh(@seats[0]).number_of_wins
      assert_equal 1, fresh(@seats[1]).number_of_wins
    end

    test "superseded rows feed neither opponents beaten nor seat counts" do
      TournamentBuilder.play_round!(@t, winners: { 1 => 0 })
      seats_before = @seats.map { |p| fresh(p).seat_counts }

      Apply.call(pod: @pod, type: "Win", winner: @seats[1])

      assert_equal 0, fresh(@seats[0]).opponents_beaten
      assert_equal 3, fresh(@seats[1]).opponents_beaten
      assert_equal(seats_before, @seats.map { |p| fresh(p).seat_counts })
    end

    test "a closed round can be corrected again and again" do
      TournamentBuilder.play_round!(@t, winners: { 1 => 0 })
      Apply.call(pod: @pod, type: "Win", winner: @seats[1])
      Apply.call(pod: @pod, type: "Draw")

      assert_equal 12, Result.where(round: @round).count
      assert_equal %w[Draw] * 4, Result.current.where(round: @round).pluck(:type)
      assert_equal 1, fresh(@seats[1]).number_of_draws
    end

    test "warns when a later round is already published" do
      TournamentBuilder.play_round!(@t, winners: { 1 => 0 })
      assert_nil Apply.warning_for(@pod)

      @t.rounds.create!(type: SwissRound, number: 2).publish!

      assert_equal :later_round_published, Apply.warning_for(@pod)
      assert_equal :later_round_published, Apply.call(pod: @pod, type: "Draw").warning
    end

    private

    def fresh(participant)
      EventParticipant.find(participant.id)
    end
  end
end
