# frozen_string_literal: true

require "test_helper"

module Play
  # The public standings end at the table: how points and tiebreakers work is told on the event page, not under it.
  class StandingsNoHelpTest < ActionDispatch::IntegrationTest
    test "no points explanation under the standings" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :swiss)
      get play_standings_path(tournament.slug)
      assert_response :success
      assert_select "table"
      assert_select "p", text: I18n.t("standings.help.owr"), count: 0
    end
  end
end
