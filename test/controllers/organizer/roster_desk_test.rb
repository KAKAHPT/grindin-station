# frozen_string_literal: true

require "test_helper"

module Organizer
  # The roster desk view: counters, flat chips and a hidden stats row per player.
  class RosterDeskTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      @tournament.rounds.create!(type: SwissRound, number: 1)
      @tournament.event_participants.first.update!(checked_in: true, paid: true, decklist: "Kinnan, Bonder Prodigy")
      post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                              password: "password123" } }
    end

    test "each player has desk chips and a hidden stats row opened by the plus button" do
      get organizer_tournament_event_participants_path(@tournament, layout: "application")

      assert_response :success
      assert_select "[data-controller~=row-expander]"
      assert_select "#roster_count_unpaid", "3"
      assert_select "tbody tr[id^=event_participant_]", 4
      assert_select "tbody tr[id^=stats_event_participant_][hidden]", 4
      assert_select "button[data-action='row-expander#toggle'][aria-expanded=false]", 4
      assert_select "tbody", text: /Checked in/
      assert_select "tbody", text: /Not checked in/
      assert_select "tbody span[role=img][aria-label]", minimum: 4
      assert_select "tbody span", text: /\A\s*Decklist\s*\z/, count: 1
      assert_select "tbody span", text: /\A\s*No decklist\s*\z/, count: 3
      assert_select "#roster_count_no_decklist", "3"
    end
  end
end
