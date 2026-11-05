# frozen_string_literal: true

require "test_helper"

module Organizer
  # Pod card on the organizer round page: tap a player to pick the winner; only Draw is shown up front.
  class PodCardTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @round.update!(published: true, started_at: Time.current)
      @pod = @round.pods.order(:number).first
      post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                              password: "password123" } }
    end

    test "a pod that can take a result has tappable seats, hidden win forms and a visible Draw" do
      get organizer_tournament_round_path(@tournament, @round)

      assert_response :success
      assert_select "#pod_#{@pod.id}[data-controller~='pod-result']" do
        assert_select "li[data-pod-result-target=row][role=button][data-seat][data-name]", 4
        assert_select "form.hidden[data-pod-result-target=winForm][data-seat]", 4
        assert_select "form.hidden[data-pod-result-target=winForm] input[name='result[type]'][value=Win]", 4
        assert_select "[data-pod-result-target=draw] button[data-action~='pod-result#pickDraw']", text: "Draw"
        assert_select "[data-pod-result-target=draw] form.hidden[data-pod-result-target=drawForm]" do
          assert_select "input[name='result[type]'][value=Draw]"
        end
        assert_select "[data-pod-result-target=confirm][hidden]", text: /Confirm/
      end
    end

    test "the round clock has its time in the first response" do
      get organizer_tournament_round_path(@tournament, @round)

      assert_select "[data-controller=round-timer]" do |clock|
        assert_match(/\A\d{2}:\d{2}\z/, clock.text.strip)
      end
    end

    test "a closed round's clock says how long it took, not 00:00" do
      @round.update_columns(started_at: 75.minutes.ago, finished_at: 75.minutes.ago + 72.minutes + 5.seconds) # rubocop:disable Rails/SkipsModelValidations
      get organizer_tournament_round_path(@tournament, @round)

      assert_select "[data-controller=round-timer]", text: /Finished in 72:05/
      I18n.with_locale(:pt) { get organizer_tournament_round_path(@tournament, @round, locale: :pt) }
      assert_select "[data-controller=round-timer]", text: /Terminou em 72:05/
    end

    test "a completed pod is not tappable" do
      TournamentBuilder.play_round!(@tournament, winners: { @pod.number => 0 })
      get organizer_tournament_round_path(@tournament, @round)

      assert_response :success
      assert_select "#pod_#{@pod.id}:not([data-controller~='pod-result'])"
      assert_select "#pod_#{@pod.id} li[data-pod-result-target=row]", 0
    end

    test "a 1v1 pod offers the best-of-three scores after the pick and the draws behind Draw" do
      t, round, pod = one_v_one_round
      get organizer_tournament_round_path(t, round)

      assert_select "#pod_#{pod.id}[data-controller~='pod-result']" do
        assert_select "li[data-pod-result-target=row]", 2
        assert_select "form.hidden[data-pod-result-target=winForm] input[name='result[games]']", 2
        assert_select "[data-pod-result-target=confirm][hidden] button[data-pod-result-games-param]", 3
        assert_select "[data-pod-result-target=confirm] button[data-pod-result-games-param='2-0-0']", text: "2-0"
        assert_select "[data-pod-result-target=confirm] button[data-pod-result-games-param='2-1-0']", text: "2-1"
        assert_select "[data-pod-result-target=confirm] button[data-pod-result-games-param='1-0-1']" \
                      "[title^='1-0 on time'][aria-label^='1-0 on time']", text: /\A1-0\s+time\z/
        assert_select "[data-pod-result-target=draw] button[data-action~='pod-result#openDraw']", text: "Draw"
        assert_select "[data-pod-result-target=drawScores][hidden] form", 2
        assert_select "[data-pod-result-target=drawScores] form:has(input[name='result[games]'][value='1-1-1']) button",
                      text: "1-1"
        assert_select "[data-pod-result-target=drawScores] form:has(input[name='result[games]'][value='0-0-1']) button",
                      text: "0-0"
      end
    end

    test "a best-of-one pod offers 1-0 and the 0-0 draw" do
      t, round, pod = one_v_one_round(match_games: 1)
      get organizer_tournament_round_path(t, round)

      assert_select "#pod_#{pod.id}" do
        assert_select "[data-pod-result-target=confirm] button[data-pod-result-games-param]", 1
        assert_select "[data-pod-result-target=confirm] button[data-pod-result-games-param='1-0-0']", text: "1-0"
        assert_select "button[data-pod-result-games-param='1-0-1']", 0
        assert_select "[data-pod-result-target=drawScores] form", 1
        assert_select "[data-pod-result-target=drawScores] input[name='result[games]'][value='0-0-1']"
      end
    end

    test "a multiplayer pod has no score buttons" do
      get organizer_tournament_round_path(@tournament, @round)

      assert_select "#pod_#{@pod.id}" do
        assert_select "[data-pod-result-games-param]", 0
        assert_select "[data-pod-result-target=drawScores]", 0
        assert_select "input[name='result[games]']", 0
      end
    end

    test "a 1v1 score from the card is recorded and the completed card shows it" do
      t, round, pod = one_v_one_round
      a, b = pod.seatings.order(:order).map(&:event_participant)

      post organizer_tournament_round_pod_results_path(t, round, pod),
           params: { result: { type: "Win", event_participant_id: b.id, games: "2-1-0" } }

      assert_redirected_to organizer_tournament_round_path(t, round)
      assert_equal [2, 1, 0], Result.current.find_by!(round: round, event_participant: b).games
      assert_equal [1, 2, 0], Result.current.find_by!(round: round, event_participant: a).games
      get organizer_tournament_round_path(t, round)
      assert_select "#pod_#{pod.id} li[data-name='#{b.name}']", text: /2-1/
      assert_select "#pod_#{pod.id} li[data-name='#{a.name}']", text: /2-1/, count: 0
    end

    test "a best-of-three 1-0 on time from the card is recorded as 1-0-1" do
      t, round, pod = one_v_one_round
      a, b = pod.seatings.order(:order).map(&:event_participant)

      post organizer_tournament_round_pod_results_path(t, round, pod),
           params: { result: { type: "Win", event_participant_id: a.id, games: "1-0-1" } }

      assert_redirected_to organizer_tournament_round_path(t, round)
      assert_equal [1, 0, 1], Result.current.find_by!(round: round, event_participant: a).games
      assert_equal [0, 1, 1], Result.current.find_by!(round: round, event_participant: b).games
    end

    test "a 1v1 cut table resolved by time called shows no score" do
      t = TournamentBuilder.build(players: 10, organizer: event_organizers(:standard_organizer), format: "one_v_one")
      t.update_columns(swiss_rounds_count: 1, top_cut_size: 8) # rubocop:disable Rails/SkipsModelValidations
      swiss = t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(t, scores: swiss.pods.pluck(:number).index_with([2, 0]))
      t.update_column(:state, :single_elimination) # rubocop:disable Rails/SkipsModelValidations
      cut = t.rounds.create!(type: SingleEliminationRound, number: 2)
      cut.update!(published: true, started_at: Time.current)
      pod = cut.pods.order(:number).first

      Results::Timeout.call(pod: pod)
      get organizer_tournament_round_path(t, cut)

      assert_equal [[0, 0, 0]],
                   Result.current.where(round: cut, event_participant: pod.event_participants).map(&:games).uniq
      assert_select "#pod_#{pod.id} li[data-name]", 2
      assert_select "#pod_#{pod.id} li[data-name]", text: /·|\d-\d/, count: 0
    end

    test "a 1v1 result without a score is refused with the reason" do
      t, round, pod = one_v_one_round
      winner = pod.seatings.first.event_participant

      assert_no_difference -> { Result.count } do
        post organizer_tournament_round_pod_results_path(t, round, pod),
             params: { result: { type: "Win", event_participant_id: winner.id } }
      end

      assert_response :unprocessable_content
      assert_includes response.body, I18n.t("results.not_allowed.score_required")
      assert_select "select[name='result[games]']"
    end

    private

    def one_v_one_round(match_games: 3)
      t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), format: "one_v_one",
                                  match_games: match_games)
      round = t.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true, started_at: Time.current)
      [t, round, round.pods.order(:number).first]
    end
  end
end
