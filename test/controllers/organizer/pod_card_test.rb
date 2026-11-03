# frozen_string_literal: true

require "test_helper"

module Organizer
  # Pod card on the organizer round page: tap a player to pick the winner; only Draw is shown up front.
  class PodCardTest < ActionDispatch::IntegrationTest
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
        assert_select "[data-pod-result-target=draw] form:not(.hidden) button", text: "Draw"
        assert_select "[data-pod-result-target=confirm][hidden]"
      end
    end

    test "a completed pod is not tappable" do
      TournamentBuilder.play_round!(@tournament, winners: { @pod.number => 0 })
      get organizer_tournament_round_path(@tournament, @round)

      assert_response :success
      assert_select "#pod_#{@pod.id}:not([data-controller~='pod-result'])"
      assert_select "#pod_#{@pod.id} li[data-pod-result-target=row]", 0
    end
  end
end
