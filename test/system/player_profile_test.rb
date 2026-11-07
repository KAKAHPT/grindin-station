# frozen_string_literal: true

require "application_system_test_case"

# The public profile in the browser: the events table shows six rows, filters by search, year and season (the
# band follows the visible rows) and the "+" opens an event's detail row.
class PlayerProfileTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(name: "Rita Grind", handle: "rita", email_address: "rita@example.com", password: "password123")
    standard = circuits(:standard_circuit)
    second = Circuit.create!(name: "Second Circuit", event_organizer: event_organizers(:standard_organizer))
    [
      ["Lisbon Open", Date.new(2026, 10, 10), "Kinnan, Bonder Prodigy", standard, 1],
      ["Porto Cup", Date.new(2026, 9, 12), "Tymna the Weaver", second, 2],
      ["Braga Masters", Date.new(2026, 7, 4), "Kinnan, Bonder Prodigy", standard, 3],
      ["Faro Weekly", Date.new(2026, 5, 2), "Rograkh, Son of Rohgahh", second, 4],
      ["Coimbra Classic", Date.new(2026, 3, 7), "Kinnan, Bonder Prodigy", nil, 2],
      ["Aveiro Clash", Date.new(2025, 11, 15), "Najeela, the Blade-Blossom", standard, 1],
      ["Evora Grind", Date.new(2025, 8, 9), "Tymna the Weaver", second, 3],
      ["Setubal Showdown", Date.new(2025, 4, 5), "Sisay, Weatherlight Captain", standard, 4]
    ].each { |name, date, commander, circuit, position| finished_event(name, date, commander, circuit, position) }
  end

  test "the detail row opens with + and closes with the same button" do
    visit profile_path("rita")
    button = first("tr[data-event] button[aria-controls]")
    detail = find("##{button['aria-controls']}", visible: :all)

    button.click
    assert detail.visible?
    assert_equal "true", button["aria-expanded"]

    button.click
    assert_not detail.visible?
    assert_equal "false", button["aria-expanded"]
  end

  test "six rows, show all, search, year, season, details and an empty filter" do
    visit profile_path("rita")

    assert_selector "tr[data-event]", count: 6
    click_button "Show all 8 events"
    assert_selector "tr[data-event]", count: 8
    assert_button "Show less"

    fill_in placeholder: "Search events, organizers, commanders…", with: "kinnan"
    assert_selector "tr[data-event]", count: 3
    assert_selector "[data-stat=events]", text: "3"
    # Kinnan rows: Lisbon (1st), Braga (3rd), Coimbra (2nd) -> 1 win, 3 top-4 finishes, one commander at 3 of 3
    assert_selector "[data-ach=wins]", text: "1"
    assert_selector "[data-ach=top4]", text: "3"
    assert_selector "[data-commanders] li", count: 1, text: /Kinnan, Bonder Prodigy\s+3 · 100%/
    assert_no_button "Show less"
    fill_in placeholder: "Search events, organizers, commanders…", with: ""

    click_button "2025"
    assert_selector "button[data-year='2025'][aria-pressed=true].seg-on"
    assert_selector "[data-count]", text: "3 of 8 events"
    find("select[data-season]").select("Second Circuit")
    assert_selector "[data-count]", text: "1 of 8 events"

    assert_opens_details("Evora Grind")

    fill_in placeholder: "Search events, organizers, commanders…", with: "nothing like this"
    assert_text "No events match."
    assert_no_selector "tr[data-event]"
    assert_no_selector "tr[data-event-detail]"
    assert_selector "[data-stat=win_rate]", text: "–"
    assert_selector "[data-stat=conversion]", text: "–"
  end

  test "headers sort by click and by keyboard, the active one flips, and the stripes follow the visible rows" do
    visit profile_path("rita")
    assert_selector "tr[data-event]", count: 6

    find("th[data-sort=name]").send_keys(:enter)
    assert_selector "th[data-sort=name][aria-sort=ascending]"
    assert_equal "Aveiro Clash", first("tr[data-event] a").text
    find("th[data-sort=name]").click
    assert_selector "th[data-sort=name][aria-sort=descending]"
    assert_no_selector "th[data-sort=date][aria-sort]"
    assert_equal "Setubal Showdown", first("tr[data-event] a").text

    find("th[data-sort=position]").send_keys(:space)
    assert_selector "th[data-sort=position][aria-sort=ascending]"
    assert_equal %w[1st 1st 2nd 2nd 3rd 3rd], all("tr[data-event] [data-result] b").map(&:text)
    assert_selector "tr[data-event][data-odd]", count: 3
    assert_selector "tr[data-event][data-last]", count: 1
  end

  private

  # The "+" on the event's row opens its detail row (record, seat per round) and shows "–".
  def assert_opens_details(name)
    find("tr[data-event]", text: name).find("button[aria-controls]").click
    within("tr[data-event-detail]", visible: true) do
      assert_text(/record/i) # uppercased by CSS
      assert_text "R1 · seat"
    end
    assert_selector "tr[data-event] button[aria-expanded=true] [data-sign]", text: "–"
  end

  # A finished 4-player tournament with the user (one swiss round, a draw) on `date`.
  def finished_event(name, date, commander, circuit, position)
    event = TournamentBuilder.build(players: 3, organizer: event_organizers(:standard_organizer), state: :swiss)
    me = event.event_participants.create!(player: @user.player, accepted_terms: true, decklist: commander)
    event.update_columns(name: name, start_time: date.to_time.change(hour: 14), circuit_id: circuit&.id, # rubocop:disable Rails/SkipsModelValidations
                         swiss_rounds_count: 1, top_cut_size: 0)
    event.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(event, winners: { 1 => :draw })
    me.update_columns(final_position: position) # rubocop:disable Rails/SkipsModelValidations
    event.update_column(:state, :finished) # rubocop:disable Rails/SkipsModelValidations
  end
end
