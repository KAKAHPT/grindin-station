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

    test "the path links the profile out of the dialog's frame, or says why there is none" do
      @tournament.update!(state: :finished)
      user = @winner.player.user
      user.update!(handle: "path-winner", visibility: "public")

      get play_standing_player_path(@tournament.slug, @winner)
      assert_select "a[data-path-profile=link][data-turbo-frame=_top][href=?]", profile_path("path-winner")

      user.update!(visibility: "private")
      get play_standing_player_path(@tournament.slug, @winner)
      assert_select "a[data-path-profile]", 0
      assert_select "[data-path-profile=private]", text: "This profile is private."

      @winner.player.update_columns(user_id: nil, guest_name: "Guest") # rubocop:disable Rails/SkipsModelValidations
      get play_standing_player_path(@tournament.slug, @winner)
      assert_select "[data-path-profile=none]", text: "This player has no profile."
    end

    test "the player who advances from the final reads Winner, the others Eliminated" do
      @tournament.update_columns(top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      final = @tournament.rounds.create!(type: SingleEliminationRound, number: 2)
      final.update!(published: true, started_at: 1.hour.ago)
      seats = final.pods.first.seatings.order(:order).map(&:event_participant)
      seats.each_with_index { |p, i| (i.zero? ? Advance : Eliminated).create!(round: final, event_participant: p) }
      final.update!(finished_at: Time.current)
      @tournament.update_columns(state: Tournament.states[:finished]) # rubocop:disable Rails/SkipsModelValidations

      get play_standing_player_path(@tournament.slug, seats.first)
      assert_select "[data-path-round='2']" do
        assert_select "b", text: "Finals"
        assert_select "[data-path-result=winner]", text: /Winner/
      end
      get play_standing_player_path(@tournament.slug, seats.last)
      assert_select "[data-path-round='2'] [data-path-result=eliminated]"
    end

    test "an unknown player, or one of another event, answers 404" do
      @tournament.update!(state: :finished)
      other = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))

      get play_standing_player_path(@tournament.slug, other.event_participants.first)
      assert_response :not_found
    end
  end
end
