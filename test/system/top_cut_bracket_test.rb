# frozen_string_literal: true

require "application_system_test_case"

# The public top-cut bracket in a real browser: the wires bracket_controller draws, long names kept inside
# their card, and one stage at a time through the tabs on a phone.
class TopCutBracketTest < ApplicationSystemTestCase
  LONG_NAME = "Maximiliano Alexandre Figueiredo de Albuquerque Sampaio"

  setup do
    @tournament = TournamentBuilder.build(players: 40, organizer: event_organizers(:standard_organizer),
                                          state: :single_elimination)
    @tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 40) # rubocop:disable Rails/SkipsModelValidations
    @tournament.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(@tournament, winners: (1..10).index_with(0))
    cut = @tournament.rounds.create!(type: SingleEliminationRound, number: 2)
    cut.update!(published: true, started_at: 5.minutes.ago)
    cut.pods.order(:number).first.seatings.order(:order).first.event_participant.player.user
      .update!(name: LONG_NAME)
  end

  test "on a desktop every stage shows, wired to the next, and a long name stays inside its card" do
    visit play_pairings_path(@tournament.slug)

    assert_selector "[data-bracket-stage]", count: 3, visible: :visible
    assert_selector "[data-bracket-stage='2'] article[data-pairing-table]", count: 8
    assert_selector "[data-bracket-stage='3'] [data-placeholder-table]", count: 4
    assert_selector "[data-bracket-stage='4'] [data-placeholder-table]", count: 1
    assert_no_selector "[data-bracket-target=tabs]", visible: :visible
    assert_selector "[data-name='#{LONG_NAME}']"

    wires = page.evaluate_script("document.querySelector('[data-bracket-target=wires] path').getAttribute('d')")
    # One stem down from each of the 9 first-stage cards (byes + 8 tables), one up into each of the 4 + 1 next.
    assert_operator wires.scan("V").size, :>=, 9 + 4 + 4 + 1
    assert overflowing_names.empty?, "names leave their card: #{overflowing_names.inspect}"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=,
                    page.evaluate_script("window.innerWidth")
  end

  test "on a phone one stage shows at a time and the tabs switch it" do
    use_phone_viewport(width: 375, height: 812)

    visit play_pairings_path(@tournament.slug)

    assert_selector "[data-bracket-stage='2']", visible: :visible
    assert_no_selector "[data-bracket-stage='3']", visible: :visible
    assert_no_selector "[data-bracket-target=wires]", visible: :visible
    assert overflowing_names.empty?, "names leave their card: #{overflowing_names.inspect}"

    within("[data-bracket-target=tabs]") { click_button "Finals" }

    assert_selector "[data-bracket-stage='4'] [data-placeholder-table]", count: 1, visible: :visible
    assert_no_selector "[data-bracket-stage='2']", visible: :visible
    assert_selector "[data-bracket-target=tab][aria-current=true]", text: "Finals"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 375
  end

  private

  # Names whose box ends past the right edge of the card they are in (1 px of rounding allowed).
  def overflowing_names
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll("[data-bracket-card] [data-name]")]
        .filter((el) => el.offsetParent !== null)
        .filter((el) => el.getBoundingClientRect().right > el.closest("[data-bracket-card]").getBoundingClientRect().right + 1)
        .map((el) => el.dataset.name)
    JS
  end
end
