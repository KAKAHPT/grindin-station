# frozen_string_literal: true

require "test_helper"

# The player and public pages load nothing from a CDN (icons come from a local sprite, Flowbite only
# in the organizer layout) and carry the phone meta tags.
class PlayLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.rounds.create!(type: SwissRound, number: 1)
  end

  test "the play and public pages have no cdn.jsdelivr.net reference" do
    [play_event_path(@tournament.slug), play_standings_path(@tournament.slug),
     play_pairings_path(@tournament.slug), profile_path(users(:player_one).handle)].each do |path|
      get path

      assert_response :success
      assert_not_includes response.body, "cdn.jsdelivr.net", path
      assert_select "meta[name=theme-color][content='#111315']"
      assert_select "meta[name=description][content]"
      assert_select "main", 1
    end
  end

  test "the organizer layout keeps Flowbite through the organizer entry point" do
    get root_path

    assert_includes response.body, %(import "organizer")
    assert_not_includes response.body, "@phosphor-icons/web"
  end
end
