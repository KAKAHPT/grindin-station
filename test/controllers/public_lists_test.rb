# frozen_string_literal: true

require "test_helper"

# The public lists (/events, /tournaments, /leagues, /circuits) on the M7 design: event tickets, the Upcoming · Past
# switch, the league page and the circuit standings card.
class PublicListsTest < ActionDispatch::IntegrationTest
  test "events lists tournaments and leagues as tickets, a tournament to /t/:slug and a league to /leagues/:id" do
    get events_path

    assert_response :success
    tournament = events(:medium_tournament)
    league = leagues(:standard_league)
    page = play_event_path(tournament.slug)
    assert_select "[data-upcoming-event=?] a[href=?]", tournament.slug, page, text: "View event"
    assert_select "[data-upcoming-event=?] a[href=?]", tournament.slug, page, text: "Register"
    assert_select "[data-upcoming-event=?] a[href=?]", league.slug, league_path(league), text: "View event"
    assert_select "[data-upcoming-event=?] a[data-register]", league.slug, count: 0
    assert_select "[data-list-filter] a.seg-on", text: "Upcoming"
  end

  test "past events show finished tournaments and mark Past" do
    get events_path(filter: "past")

    assert_response :success
    assert_select "[data-upcoming-event=?]", events(:finished_tournament).slug
    assert_select "[data-upcoming-event=?]", events(:medium_tournament).slug, count: 0
    assert_select "[data-list-filter] a.seg-on", text: "Past"
  end

  test "tournaments and leagues indexes render tickets in Portuguese" do
    get tournaments_path(locale: "pt")
    assert_select "h1", text: "Torneios"
    assert_select "[data-upcoming-event=?]", events(:medium_tournament).slug

    get leagues_path(locale: "pt")
    assert_select "h1", text: "Ligas"
    assert_select "[data-upcoming-event=?]", leagues(:standard_league).slug
  end

  test "the league page has the event header and the About card" do
    league = leagues(:standard_league)

    get league_path(league)

    assert_response :success
    assert_select "[data-event-header] h1", text: league.name
    assert_select "[data-about] .card-title", text: "About"
  end

  test "a circuit's standings show rank, player, points and events, best first" do
    circuit = circuits(:standard_circuit)
    circuit.circuit_standings.create!(player: players(:player_one), points: 5, events_count: 1)
    circuit.circuit_standings.create!(player: players(:player_two), points: 12, events_count: 2)

    get circuit_path(circuit)

    assert_response :success
    assert_select "[data-circuit-standings] tbody tr", 2
    assert_select "[data-circuit-standings] tbody tr:first-child td", text: "12"
    assert_select "[data-circuit-standings] tbody tr:first-child td", text: players(:player_two).name
  end
end
