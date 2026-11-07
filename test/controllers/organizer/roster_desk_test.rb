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

    test "a waitlisted player is listed with their waitlist position, not a rank" do
      waiting = @tournament.event_participants.create!(player_name: "Espera Um", accepted_terms: true,
                                                       player_email: "espera-#{SecureRandom.hex(3)}@example.com")
      waiting.update_columns(waitlisted: true, waitlist_position: 1) # rubocop:disable Rails/SkipsModelValidations

      get organizer_tournament_event_participants_path(@tournament)

      assert_response :success
      ranks = css_select("tbody tr[id^=event_participant_] th:first-child").map { |th| th.text.strip }
      assert_equal %w[1 2 3 4], ranks.first(4)
      assert_select "##{ActionView::RecordIdentifier.dom_id(waiting)} th:first-child", text: "Waitlist #1"

      get organizer_tournament_event_participants_path(@tournament, layout: "application")

      assert_select "tbody tr[id^=event_participant_]", 4, "the waitlist leaves the roster table"
      assert_select "[data-waitlist] [data-waitlist-row='#{waiting.id}']" do
        assert_select "td:first-child", text: "1"
        assert_select "th", text: "Espera Um"
        assert_select "form[action=?]", promote_organizer_tournament_event_participant_path(@tournament, waiting),
                      count: 0, "no Add to bracket once the swiss started"
        assert_select "form[action=?] button", drop_organizer_tournament_event_participant_path(@tournament, waiting),
                      text: /Remove/
      end

      get organizer_tournament_event_participants_path(@tournament, layout: "application", status: "waitlisted")

      assert_select "tbody tr[id^=event_participant_]", 0
      assert_select "[data-waitlist] [data-waitlist-row]", 1
      assert_select "#roster_count_waitlisted", "1"
    end
  end
end
