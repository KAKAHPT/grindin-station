# frozen_string_literal: true

require "test_helper"

module Play
  # The public standings (and the list of enrolled players before the start) show 20 players per page.
  class StandingsPagesTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 24, organizer: event_organizers(:standard_organizer))
    end

    test "24 players: 20 on the first page with Next, the last 4 on the second, numbered on from 21" do
      get play_standings_path(@tournament.slug)

      assert_select "tbody tr", 20
      assert_select "[data-standings-pages]", text: /Page 1 of 2/
      second = play_standings_path(@tournament.slug, page: 2)
      assert_select "[data-standings-pages] a[rel=next][href=?]", second, text: /Next/
      assert_select "[data-standings-pages] a[rel=prev]", count: 0

      get play_standings_path(@tournament.slug, page: 2)

      assert_select "tbody tr", 4
      assert_select "tbody tr:first-child th:first-child", text: "21"
      assert_select "[data-standings-pages] a[rel=prev]", text: /Previous/
      assert_select "[data-standings-pages] a[rel=next]", count: 0
    end

    test "20 players or fewer: one page and no pager; the organizer modal lists everyone" do
      @tournament.event_participants.order(:created_at).last(4).each(&:destroy!)
      get play_standings_path(@tournament.slug)

      assert_select "tbody tr", 20
      assert_select "[data-standings-pages]", count: 0

      big = TournamentBuilder.build(players: 24, organizer: event_organizers(:standard_organizer))
      get tournament_event_participants_path(big), headers: { "Turbo-Frame" => "modal" }

      assert_select "tbody tr", 24
      assert_select "[data-standings-pages]", count: 0
    end

    test "a signed-in player lands on the page their own row is on; page 1 is still one click away" do
      get play_standings_path(@tournament.slug, page: 2)
      last_row = css_select("tbody tr").last["id"].delete_prefix("event_participant_")
      me = @tournament.event_participants.find(last_row)
      me.player.user.update!(password: "password123")
      post session_path, params: { session: { email_address: me.player.user.email_address, password: "password123" } }

      get play_standings_path(@tournament.slug)

      assert_select "[data-standings-pages]", text: /Page 2 of 2/
      assert_select "tr#event_participant_#{me.id}[data-me]", count: 1
      assert_select "[data-standings-pages] a[rel=prev][href=?]", play_standings_path(@tournament.slug, page: 1)

      get play_standings_path(@tournament.slug, page: 1)

      assert_select "[data-standings-pages]", text: /Page 1 of 2/
      assert_select "tr[data-me]", count: 0
    end
  end
end
