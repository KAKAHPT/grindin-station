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

  test "index counts only the open tournament" do
    get circuits_path

    assert_response :success
    assert_select "[data-circuit=?] [data-circuit-events]", @circuit.id, text: /\b1 event\b/
  end
end
