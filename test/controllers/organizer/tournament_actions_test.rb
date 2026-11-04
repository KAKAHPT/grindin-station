# frozen_string_literal: true

require "test_helper"

module Organizer
  # The tournament page offers only the state changes the transition map allows.
  class TournamentActionsTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
      @t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    end

    test "a running tournament can be canceled" do
      get organizer_tournament_path(@t)

      assert_select "form[action='#{organizer_tournament_path(@t)}'] input[name='tournament[state]'][value=canceled]"
    end

    test "a finished tournament offers no cancel and refuses one" do
      @t.update_column(:state, Tournament.states[:finished]) # rubocop:disable Rails/SkipsModelValidations

      get organizer_tournament_path(@t)
      assert_select "input[name='tournament[state]'][value=canceled]", count: 0

      patch organizer_tournament_path(@t), params: { tournament: { state: "canceled" } }
      assert_response :unprocessable_entity
      assert_predicate @t.reload, :finished?
    end
  end
end
