# frozen_string_literal: true

require "test_helper"

module Play
  # The public standings show a player's picture before the name when the account has one.
  class StandingsAvatarTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :swiss)
      @pictured = @tournament.event_participants.find { |participant| participant.player.user }
    end

    test "a player with a picture shows it; the others keep an empty slot so names stay aligned" do
      @pictured.player.user.avatar.attach(io: file_fixture("cover1.jpg").open, filename: "a.jpg",
                                          content_type: "image/jpeg")
      get play_standings_path(@tournament.slug)

      assert_response :success
      assert_select "tr##{dom_id(@pictured)} img[data-standings-avatar]", 1
      assert_select "img[data-standings-avatar]", 1
      assert_select "tbody tr th span.size-5[aria-hidden]", 3
    end

    test "no picture slot at all while nobody has a picture" do
      get play_standings_path(@tournament.slug)

      assert_response :success
      assert_select "img[data-standings-avatar]", 0
      assert_select "tbody tr th span.size-5[aria-hidden]", 0
    end
  end
end
