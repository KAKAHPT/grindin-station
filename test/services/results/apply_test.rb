# frozen_string_literal: true

require "test_helper"

module Results
  class ApplyTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
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

    test "a multiplayer result leaves the game columns at zero" do
      Apply.call(pod: @pod, type: "Win", winner: @seats[0], by: @user)

      assert_equal [[0, 0, 0]], Result.where(round: @round).map(&:games).uniq
    end

    test "1v1: a win writes the winner's games and the mirror on the loser" do
      pod, a, b = one_v_one_pod

      Apply.call(pod: pod, type: "Win", winner: b, games: { winner: [2, 1, 0] })

      assert_equal [2, 1, 0], current(pod, b).games
      assert_equal [1, 2, 0], current(pod, a).games
      assert_equal %w[Loss Win], [current(pod, a).type, current(pod, b).type]
    end

    test "1v1: an open round updated in place rewrites the games" do
      pod, a, b = one_v_one_pod
      Apply.call(pod: pod, type: "Win", winner: a, games: { winner: [2, 0, 0] })
      ids = Result.where(round: pod.round).order(:id).pluck(:id)

      Apply.call(pod: pod, type: "Draw", games: { games: [1, 1, 1] })

      assert_equal ids, Result.where(round: pod.round).order(:id).pluck(:id)
      assert_equal [[1, 1, 1]], [current(pod, a).games, current(pod, b).games].uniq
    end

    test "1v1: a closed round superseded keeps the games on the fresh rows" do
      pod, a, b = one_v_one_pod
      TournamentBuilder.play_1v1_round!(pod.event, scores: { pod.number => [2, 0] })

      Apply.call(pod: pod, type: "Win", winner: b, games: { winner: [2, 1, 0] })

      assert_equal 4, Result.where(round: pod.round).count
      assert_equal [2, 1, 0], current(pod, b).games
      assert_equal [1, 2, 0], current(pod, a).games
    end

    test "1v1: string keys and string numbers (pending JSON, params) are accepted" do
      pod, a, = one_v_one_pod

      Apply.call(pod: pod, type: "Win", winner: a, games: { "winner" => %w[2 0 0] })

      assert_equal [2, 0, 0], current(pod, a).games
    end

    test "1v1 best-of-three allows 2-0, 2-1 and the draws 1-1-1, 1-1-0, 0-0-1" do
      pod, a, = one_v_one_pod
      [[:winner, [2, 0, 0]], [:winner, [2, 1, 0]], [:games, [1, 1, 1]], [:games, [1, 1, 0]],
       [:games, [0, 0, 1]]].each do |key, games|
        type = key == :winner ? "Win" : "Draw"
        Apply.call(pod: pod, type: type, winner: a, games: { key => games })

        assert_equal games, current(pod, a).games
      end
    end

    test "1v1 refuses impossible scores" do
      pod, a, = one_v_one_pod
      [{ winner: [2, 2, 0] }, { winner: [3, 0, 0] }, { winner: [1, 0, 0] }, { winner: [-1, 0, 0] },
       { winner: [2, 0] }, { games: [2, 1, 0] }, { games: [0, 0, 0] }].each do |games|
        type = games.key?(:winner) ? "Win" : "Draw"
        error = assert_raises(NotAllowed) { Apply.call(pod: pod, type: type, winner: a, games: games) }

        assert_equal "impossible_score", error.message
      end
      assert_equal 0, Result.where(round: pod.round).count
    end

    test "1v1 best-of-one allows 1-0 and the drawn game, nothing else" do
      pod, a, = one_v_one_pod(match_games: 1)
      Apply.call(pod: pod, type: "Win", winner: a, games: { winner: [1, 0, 0] })
      assert_equal [1, 0, 0], current(pod, a).games
      Apply.call(pod: pod, type: "Draw", games: { games: [0, 0, 1] })
      assert_equal [0, 0, 1], current(pod, a).games

      error = assert_raises(NotAllowed) { Apply.call(pod: pod, type: "Win", winner: a, games: { winner: [2, 0, 0] }) }
      assert_equal "impossible_score", error.message
    end

    test "1v1 needs a score unless it is a penalty" do
      pod, a, = one_v_one_pod
      %w[Win Draw].each do |type|
        error = assert_raises(NotAllowed) { Apply.call(pod: pod, type: type, winner: a) }

        assert_equal "score_required", error.message
      end

      Apply.call(pod: pod, type: "Penalty", winner: a)
      assert_equal "Penalty", current(pod, a).type
    end

    private

    # A started 1v1 swiss round's first pod and its two players in seat order.
    def one_v_one_pod(match_games: 3)
      t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), format: "one_v_one")
      t.update!(match_games: match_games)
      pod = t.rounds.create!(type: SwissRound, number: 1).pods.order(:number).first
      [pod, *pod.seatings.order(:order).map(&:event_participant)]
    end

    def current(pod, participant)
      Result.current.find_by!(round: pod.round, event_participant: participant)
    end

    def fresh(participant)
      EventParticipant.find(participant.id)
    end
  end
end
