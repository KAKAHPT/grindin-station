# frozen_string_literal: true

require "test_helper"

class BrandingTest < ActionDispatch::IntegrationTest
  test "home page is branded Grindin Station" do
    get root_path
    assert_response :success
    assert_select "title", /Grindin Station/
    assert_no_match(/Canivete/, response.body)
  end

  test "the app is dark by default on the palette A ground" do
    get root_path
    assert_select "body.bg-ground.text-ink.font-body"
    assert_select "link[href*='fonts.googleapis.com'][href*=Sora][href*=Manrope]"
    assert_no_match(/bg-(purple|orange)-/, response.body)
  end

  test "the standings page uses the palette A ground" do
    tournament = build_round_tournament
    get play_standings_path(tournament.slug)

    assert_response :success
    assert_select "[class~=bg-ground]"
    assert_no_match(/bg-(purple|orange)-/, response.body)
  end

  test "the standings page opened as a page gets the full play layout" do
    tournament = build_round_tournament
    get play_standings_path(tournament.slug)

    assert_response :success
    assert_includes response.body, "<html"
    assert_select "body.bg-ground"
    assert_select "nav[data-play-nav]"
    assert_select "turbo-frame#modal", count: 0
  end

  test "the standings page inside the modal frame stays a modal" do
    tournament = build_round_tournament
    get tournament_event_participants_path(tournament), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "turbo-frame#modal"
    assert_select "[class~=bg-ground]"
    assert_not_includes response.body, "<html"
  end

  test "the organizer round, roster and judge center pages have no purple or orange" do
    tournament = build_round_tournament
    round = tournament.rounds.first
    round.update!(started_at: Time.current)
    round.pods.first.update!(extra_time: 5)
    post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                            password: "password123" } }

    [organizer_tournament_round_path(tournament, round),
     organizer_tournament_event_participants_path(tournament, layout: "application"),
     organizer_tournament_judge_calls_path(tournament)].each do |path|
      get path
      assert_response :success
      assert_select "body.bg-ground"
      assert_no_match(/(bg|text|border)-(purple|orange)-/, response.body, path)
    end
  end

  test "the player table page uses the palette A ground" do
    tournament = build_round_tournament
    round = tournament.rounds.first
    participant = round.pods.order(:number).first.event_participants.first
    participant.player.user.update!(password: "password123")
    post session_path, params: { session: { email_address: participant.player.user.email_address,
                                            password: "password123" } }

    get play_me_path(tournament.slug)

    assert_response :success
    assert_select "body.bg-ground.text-ink"
    assert_select "[data-table-number].font-display"
    assert_no_match(/(bg|text|border)-(purple|orange)-/, response.body)
  end

  private

  def build_round_tournament
    tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    tournament.rounds.create!(type: SwissRound, number: 1).update!(published: true)
    tournament
  end
end
