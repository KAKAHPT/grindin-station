# frozen_string_literal: true

require "test_helper"

module Organizer
  # Keyboard and screen-reader basics on the organizer pages: the round clock is a real button, the tappable seats
  # answer Enter and Space, and the search fields carry a translated name.
  class RoundPageAccessibilityTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @round.update!(published: true, started_at: Time.current)
      post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                              password: "password123" } }
    end

    test "the round clock is a button that opens the full-screen clock" do
      get organizer_tournament_round_path(@tournament, @round)

      assert_select "button[type=button][data-controller=round-timer]" \
                    "[data-action='click->round-timer#toggleFullscreen']"
      assert_select "span[data-controller=round-timer]", 0
    end

    test "a tappable seat answers Enter and Space" do
      get organizer_tournament_round_path(@tournament, @round)

      assert_select "li[data-pod-result-target=row][role=button][tabindex='0']" do |rows|
        rows.each do |row|
          assert_includes row["data-action"], "keydown.enter->pod-result#select"
          assert_includes row["data-action"], "keydown.space->pod-result#select"
          assert_includes row["class"], "focus-visible:outline-accent"
        end
      end
    end

    test "the player searches are named in the page's language" do
      get organizer_tournament_round_path(@tournament, @round, locale: "pt")
      assert_select "input#table-search[aria-label='Procurar jogadores'][placeholder='Procurar jogadores']"

      get organizer_tournament_event_participants_path(@tournament, layout: "application", locale: "es")
      assert_select "input[name=query][aria-label='Buscar jugadores'][placeholder='Buscar jugadores']"
    end
  end
end
