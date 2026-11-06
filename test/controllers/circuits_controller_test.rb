# frozen_string_literal: true

require "test_helper"

# A visitor sees a circuit's open events only: drafts and canceled events stay out of the lists and the counts.
class CircuitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @circuit = circuits(:standard_circuit)
    organizer = event_organizers(:standard_organizer)
    @open = Tournament.create!(name: "Open One", event_organizer: organizer, circuit: @circuit,
                               state: :registration_open, start_time: 1.week.from_now, end_time: 2.weeks.from_now)
    @draft = Tournament.create!(name: "Draft One", event_organizer: organizer, circuit: @circuit,
                                state: :draft, start_time: 1.week.from_now, end_time: 2.weeks.from_now)
  end

  test "show lists only the open tournament and counts it alone" do
    get circuit_path(@circuit)

    assert_response :success
    assert_includes response.body, "Open One"
    assert_not_includes response.body, "Draft One"
    assert_select "[data-circuit-events]", text: /\b1 event\b/
  end

  test "standings stop at 16 with Show all; events switch between upcoming and past" do
    organizer = event_organizers(:standard_organizer)
    Tournament.create!(name: "Past One", event_organizer: organizer, circuit: @circuit, state: :finished,
                       start_time: 3.weeks.ago, end_time: 3.weeks.ago + 8.hours)
    20.times do |i|
      player = Player.create!(key: "circuit-#{i}-#{SecureRandom.hex(3)}", guest_name: "Grinder #{i}")
      @circuit.circuit_standings.create!(player: player, points: 100 - i, events_count: 1)
    end

    get circuit_path(@circuit)
    assert_select "[data-circuit-standings] tbody tr", 16
    assert_select "[data-circuit-standings] a[data-show-all][href=?]", circuit_path(@circuit, all: 1),
                  text: "Show all 20"
    assert_select "[data-circuit-players]", text: "20 players ranked"
    assert_select "[data-ticket-grid] [data-upcoming-event='open-one']"
    assert_select "[data-ticket-grid] [data-upcoming-event='past-one']", 0

    get circuit_path(@circuit, all: 1, filter: "past")
    assert_select "[data-circuit-standings] tbody tr", 20
    assert_select "[data-circuit-standings] a[data-show-top]"
    assert_select "[data-circuit-events-switch] a.seg-on", text: "Past"
    assert_select "[data-ticket-grid] [data-upcoming-event='past-one']"
    assert_select "[data-ticket-grid] [data-upcoming-event='open-one']", 0
    # The hero still points at the open event.
    assert_select "[data-circuit-register][href=?]", play_event_path("open-one")
    assert_select "[data-circuit-events]", text: /\b2 events\b/
  end

  test "index counts only the open tournament" do
    get circuits_path

    assert_response :success
    assert_select "[data-circuit=?] [data-circuit-events]", @circuit.id, text: /\b1 event\b/
  end
  test "index sorts featured first by default, by name or by organizer on request" do
    other_user = User.create!(name: "Aveiro Org", handle: "aveiro-org", password: "password123",
                              email_address: "aveiro-#{SecureRandom.hex(3)}@example.com")
    other = EventOrganizer.create!(user: other_user)
    zed = Circuit.create!(name: "Zed Circuit", event_organizer: other, featured: true)
    alpha = Circuit.create!(name: "Alpha Circuit", event_organizer: event_organizers(:standard_organizer))

    get circuits_path
    assert_order zed, alpha, @circuit
    assert_select "select[name=sort] option[selected][value=featured]"

    get circuits_path(sort: "name")
    assert_order alpha, @circuit, zed

    get circuits_path(sort: "organizer")
    assert_order zed, alpha, @circuit
  end

  private

  def circuit_ids_in_page = css_select("[data-circuit]").pluck("data-circuit")

  # These circuits come in this order on the page (other listed circuits ignored).
  def assert_order(*circuits)
    assert_equal circuits.map(&:id), circuit_ids_in_page & circuits.map(&:id)
  end
end
