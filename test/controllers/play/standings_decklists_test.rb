# frozen_string_literal: true

require "test_helper"

module Play
  # Final standings with "show decklists" on: an icon beside the name opens the link the player gave.
  class StandingsDecklistsTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 0, show_decklists: true) # rubocop:disable Rails/SkipsModelValidations
      @tournament.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
      @linked, @named, @unsafe = @tournament.event_participants.order(:created_at).first(3)
      @linked.update_columns(decklist: "https://moxfield.com/decks/abc123") # rubocop:disable Rails/SkipsModelValidations
      @named.update_columns(decklist: "Tymna / Kraum") # rubocop:disable Rails/SkipsModelValidations
      @unsafe.update_columns(decklist: "javascript:alert(1)") # rubocop:disable Rails/SkipsModelValidations
    end

    test "no link while the event runs" do
      get play_standings_path(@tournament.slug)

      assert_select "a[data-decklist-link]", 0
    end

    test "finished with the setting on: only a web link gets the icon, opening in a new tab" do
      @tournament.update!(state: :finished)
      get play_standings_path(@tournament.slug)

      assert_select "a[data-decklist-link]", 1
      assert_select "tr#event_participant_#{@linked.id} a[data-decklist-link][href=?][target=_blank][rel~=noopener]",
                    "https://moxfield.com/decks/abc123", text: /View decklist/
    end

    test "finished with the setting off: no link" do
      @tournament.update!(state: :finished, show_decklists: false)
      get play_standings_path(@tournament.slug)

      assert_select "a[data-decklist-link]", 0
    end
  end
end
