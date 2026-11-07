# frozen_string_literal: true

require "test_helper"

module Organizer
  # Declares no authorization: none of its actions may run.
  class UndeclaredTestController < OrganizerController
    def index
      head :ok
    end
  end

  class OrganizerControllerTest < ActionDispatch::IntegrationTest
    setup do
      @judged = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                        state: :registration_open)
      @judge = User.create!(name: "Judge", email_address: "judge-#{SecureRandom.hex(3)}@example.com",
                            password: "password123", organizer: true)
      @owned_by_judge = TournamentBuilder.build(players: 4, organizer: @judge.event_organizer,
                                                state: :registration_open)
      EventStaff.create!(event: @judged, user: @judge, role: "scorekeeper")
      sign_in
    end

    test "a query tournament_id does not choose the event whose role is checked" do
      patch organizer_tournament_path(@judged, tournament_id: @owned_by_judge.id),
            params: { tournament: { state: "canceled" } }
      assert_redirected_to organizer_root_path
      assert_equal I18n.t("flash.alert.not_allowed"), flash[:alert]
      assert @judged.reload.registration_open?

      get edit_organizer_tournament_path(@judged, tournament_id: @owned_by_judge.id)
      assert_redirected_to organizer_root_path
    end

    test "an action no macro declared is refused" do
      assert_not UndeclaredTestController.action_declared?("index")
      assert TournamentsController.action_declared?("index")

      rules = TournamentsController.authorization_rules
      TournamentsController.authorization_rules = [] # as if index had no declaration
      get organizer_root_path
      assert_redirected_to organizer_root_path
      assert_equal I18n.t("flash.alert.not_allowed"), flash[:alert]
    ensure
      TournamentsController.authorization_rules = rules
    end

    private

    def sign_in
      post session_path, params: { session: { email_address: @judge.email_address, password: "password123" } }
    end
  end
end
