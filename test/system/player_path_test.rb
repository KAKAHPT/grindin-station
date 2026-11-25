# frozen_string_literal: true

require "application_system_test_case"

# Final standings in a real browser: a name opens the player's path in a dialog, an opponent's name
# swaps it for theirs, and the dialog closes.
class PlayerPathTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    round = @tournament.rounds.create!(type: SwissRound, number: 1)
    round.update!(published: true, started_at: 1.hour.ago)
    TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
    @winner, @loser = round.pods.find_by!(number: 1).seatings.order(:order).first(2).map(&:event_participant)
    @tournament.update!(state: :finished)
  end

  test "a name opens the path, an opponent's name shows theirs, and the dialog closes" do
    visit play_standings_path(@tournament.slug)
    assert_no_selector "dialog[data-player-path-dialog][open]"

    click_link @winner.name
    within "dialog[data-player-path-dialog][open]" do
      assert_selector "h3", text: @winner.name
      assert_selector "[data-path-result=win]"
      click_link @loser.name
      assert_selector "h3", text: @loser.name
      assert_selector "[data-path-result=loss]"
      find("button[data-action='player-path#close']").click
    end
    assert_no_selector "dialog[data-player-path-dialog][open]"
    assert_no_selector "turbo-frame#player_path h3", visible: :all
  end

  test "View profile in the dialog opens the player's profile page" do
    @winner.player.user.update!(handle: "path-winner", visibility: "public")
    visit play_standings_path(@tournament.slug)

    click_link @winner.name
    within("dialog[data-player-path-dialog][open]") { click_link "View profile" }

    assert_current_path profile_path("path-winner")
    assert_no_text "Content missing"
  end
end
