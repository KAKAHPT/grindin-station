# frozen_string_literal: true

require "test_helper"

module Organizer
  class StaffControllerTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                            state: :registration_open)
    end

    test "the owner adds an existing user by e-mail and removes them" do
      assert_difference -> { @tournament.event_staff.count }, 1 do
        post organizer_tournament_staff_index_path(@tournament),
             params: { event_staff: { email_address: users(:player_one).email_address.upcase, role: "judge" } }
      end
      assert_redirected_to organizer_tournament_staff_index_path(@tournament)
      staff = @tournament.event_staff.last
      assert_equal [users(:player_one), "judge"], [staff.user, staff.role]

      get organizer_tournament_staff_index_path(@tournament)
      assert_select "li", text: /Player One/

      assert_difference -> { @tournament.event_staff.count }, -1 do
        delete organizer_tournament_staff_path(@tournament, staff)
      end
    end

    test "an unknown e-mail is an error and adds nobody" do
      assert_no_difference -> { EventStaff.count } do
        post organizer_tournament_staff_index_path(@tournament),
             params: { event_staff: { email_address: "nobody@example.com", role: "judge" } }
      end
      assert_redirected_to organizer_tournament_staff_index_path(@tournament)
      assert_equal I18n.t("flash.alert.staff_user_not_found"), flash[:alert]
    end
  end
end
