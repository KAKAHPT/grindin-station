# frozen_string_literal: true

require "test_helper"

module Organizer
  class JudgeCenterTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @pod = @round.pods.first
      @users = { "organizer" => users(:organizer_user) }
      %w[judge scorekeeper].each do |role|
        user = User.create!(name: role.capitalize, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
        EventStaff.create!(event: @tournament, user: user, role: role)
        @users[role] = user
      end
      @call = JudgeCalls::Open.call(event: @tournament, pod: @pod, participant: @pod.event_participants.first,
                                    reason: "Stack question")
    end

    test "a judge sees the open calls" do
      sign_in_as("judge")
      get organizer_tournament_judge_calls_path(@tournament)

      assert_response :success
      assert_includes response.body, "Stack question"
      assert_includes response.body, @pod.event_participants.first.player.name
    end

    test "a judge acknowledges and closes a call" do
      sign_in_as("judge")
      patch acknowledge_organizer_tournament_judge_call_path(@tournament, @call)
      assert_redirected_to organizer_tournament_judge_calls_path(@tournament)
      assert @call.reload.acknowledged?

      patch close_organizer_tournament_judge_call_path(@tournament, @call)
      assert_redirected_to organizer_tournament_judge_calls_path(@tournament)
      assert @call.reload.closed?
      assert_equal @users["judge"], @call.acknowledged_by
    end

    test "a scorekeeper is turned away" do
      sign_in_as("scorekeeper")
      get organizer_tournament_judge_calls_path(@tournament)
      assert_response :redirect

      patch close_organizer_tournament_judge_call_path(@tournament, @call)
      assert_response :redirect
      assert @call.reload.open?
    end

    test "a call from another event is not found" do
      other = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      foreign = JudgeCall.create!(event: other, reason: "elsewhere")
      sign_in_as("judge")
      patch close_organizer_tournament_judge_call_path(@tournament, foreign)

      assert_response :not_found
      assert foreign.reload.open?
    end

    test "the owner sees the Judge Center button with the open calls count" do
      other = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      JudgeCall.create!(event: other, reason: "elsewhere")
      JudgeCall.create!(event: @tournament, reason: "second")
      JudgeCall.create!(event: @tournament, reason: "done").close!(by: @users["organizer"])
      sign_in_as("organizer")
      get organizer_tournament_path(@tournament)

      assert_response :success
      assert_select "a[href=?]", organizer_tournament_judge_calls_path(@tournament) do
        assert_select "[data-judge-calls-count]", text: "2"
      end
    end

    test "a scorekeeper does not see the Judge Center button" do
      sign_in_as("scorekeeper")
      get organizer_tournament_path(@tournament)

      assert_response :success
      assert_select "a[href=?]", organizer_tournament_judge_calls_path(@tournament), count: 0
    end

    private

    def sign_in_as(role)
      user = @users.fetch(role)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
