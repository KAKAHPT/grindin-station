# frozen_string_literal: true

require "test_helper"

module Play
  # The final standings' player dialog: a name opens that player's path through the event.
  class StandingsPlayerTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @round.update!(published: true, started_at: 1.hour.ago)
      TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
      pod = @round.pods.find_by!(number: 1)
      @winner, @loser = pod.seatings.order(:order).first(2).map(&:event_participant)
    end

    test "while the event runs, names keep their profile link and a path answers 404" do
      get play_standings_path(@tournament.slug)
      assert_select "a[data-player-path]", 0
      assert_select "dialog[data-player-path-dialog]", 0

      get play_standing_player_path(@tournament.slug, @winner)
      assert_response :not_found
    end

    test "final standings open a player's path: table, seat, result and who sat with them" do
      @tournament.update!(state: :finished)

      get play_standings_path(@tournament.slug)
      assert_select "dialog[data-player-path-dialog] turbo-frame#player_path"
      assert_select "a[data-player-path][data-turbo-frame=player_path][href=?]",
                    play_standing_player_path(@tournament.slug, @winner)

      get play_standing_player_path(@tournament.slug, @winner)
      assert_response :success
      assert_select "turbo-frame#player_path" do
        assert_select "h3", text: @winner.name
        assert_select "[data-path-round='1']", 1 do
          assert_select "[data-path-result=win]", text: /Win/
          assert_select "b", text: "Round 1"
          assert_select "span", text: /Table\s+1\s+· seat 1/
          assert_select "a[href=?]", play_standing_player_path(@tournament.slug, @loser), text: @loser.name
        end
      end

      get play_standing_player_path(@tournament.slug, @loser)
      assert_select "[data-path-result=loss]"
      assert_select "[data-path-round='1'] p", text: /#{Regexp.escape(@winner.name)}/
    end

    test "an unknown player, or one of another event, answers 404" do
      @tournament.update!(state: :finished)
      other = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))

      get play_standing_player_path(@tournament.slug, other.event_participants.first)
      assert_response :not_found
    end
  end
end
