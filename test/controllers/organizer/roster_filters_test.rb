# frozen_string_literal: true

require "test_helper"

module Organizer
  # The roster's filters (what the desk still has to do) and its pages of 20 players.
  class RosterFiltersTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 23, organizer: event_organizers(:standard_organizer),
                                            state: :registration_closed)
      @participants = @tournament.event_participants.order(:created_at, :id).to_a
      post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                              password: "password123" } }
    end

    test "the roster lists 20 players per page" do
      get roster(page: nil)

      assert_select "tbody tr[id^=event_participant_]", 20
      assert_select "[data-roster-pages]", text: /Page 1 of 2/

      get roster(page: 2)

      assert_select "tbody tr[id^=event_participant_]", 3
    end

    test "not checked in and no decklist are filters with their counts" do
      # rubocop:disable Rails/SkipsModelValidations
      @tournament.event_participants.where(id: @participants.first(2)).update_all(checked_in: true)
      @tournament.event_participants.where.not(id: @participants.last).update_all(decklist: "https://example.com/deck")
      # rubocop:enable Rails/SkipsModelValidations

      get roster(status: "not_checked_in", page: 2)

      assert_select "[data-roster-filter=not_checked_in][aria-current] b", "21"
      assert_select "tbody tr[id^=event_participant_]", 1

      get roster(status: "no_decklist")

      assert_select "tbody tr[id^=event_participant_]", 1
      assert_select "tbody tr##{ActionView::RecordIdentifier.dom_id(@participants.last)}"
    end

    test "a row action comes back to the same filter and page" do
      patch check_in_organizer_tournament_event_participant_path(@tournament, @participants.last),
            headers: { "Referer" => "http://www.example.com#{roster(status: 'not_checked_in', page: 2)}" }

      assert_redirected_to roster(status: "not_checked_in", page: 2)
      assert_predicate @participants.last.reload, :checked_in?
    end

    private

    def roster_params(**view)
      { layout: "application", **view.compact }
    end

    def roster(**view)
      organizer_tournament_event_participants_path(@tournament, roster_params(**view))
    end
  end
end
