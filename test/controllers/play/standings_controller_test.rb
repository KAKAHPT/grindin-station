# frozen_string_literal: true

require "test_helper"

module Play
  class StandingsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @tournament.update_columns(seed: 99, swiss_rounds_count: 2, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
      @tournament.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
    end

    test "a visitor sees the standings in the play layout" do
      get play_standings_path(@tournament.slug)

      assert_response :success
      assert_select "[data-event-header] h1", text: "#{@tournament.name} · Standings"
      assert_select "tbody tr", 8
      assert_select "th", text: "Seats", count: 0
      assert_select "tbody span[role=img]", count: 0
      assert_select "tr[data-me]", count: 0
      assert_select "nav[data-play-nav] a[href=?][aria-current=page]", play_standings_path(@tournament.slug)
      assert_select "turbo-frame#modal", count: 0
    end

    test "a signed-in player's row is highlighted with You; there are no seats" do
      me = @tournament.event_participants.order(:created_at).first
      me.player.user.update!(password: "password123")
      post session_path, params: { session: { email_address: me.player.user.email_address, password: "password123" } }

      get play_standings_path(@tournament.slug)

      assert_select "tr[data-me]", count: 1
      assert_select "tr#event_participant_#{me.id}[data-me] [data-you]", text: "You"
      assert_select "th", text: "Seats", count: 0
    end

    test "the organizer modal has no Seats column either" do
      get tournament_event_participants_path(@tournament), headers: { "Turbo-Frame" => "modal" }

      assert_select "tbody tr", 8
      assert_select "th", text: "Seats", count: 0
      assert_select "tbody span[role=img]", count: 0
      assert_select "tr[data-me]", count: 0
    end

    test "the page follows the event's standings stream and refreshes by morph; the modal does not" do
      signed = Turbo::StreamsChannel.signed_stream_name(LiveBroadcasts.standings_stream(@tournament.id, :en))

      get play_standings_path(@tournament.slug)

      assert_select "turbo-cable-stream-source[signed-stream-name=?]", signed
      assert_select "meta[name='turbo-refresh-method'][content='morph']"

      get tournament_event_participants_path(@tournament), headers: { "Turbo-Frame" => "modal" }

      assert_select "turbo-cable-stream-source", count: 0
    end

    test "the old standings address redirects to the new one" do
      get tournament_event_participants_path(@tournament, locale: "pt")

      assert_response :found
      assert_redirected_to play_standings_path(@tournament.slug, locale: "pt")
    end

    test "the old standings address inside the modal frame stays a modal" do
      get tournament_event_participants_path(@tournament), headers: { "Turbo-Frame" => "modal" }

      assert_response :success
      assert_select "turbo-frame#modal"
    end

    test "a finished event shows final standings with the top cut positions first" do
      ranked = @tournament.event_participants.order(:created_at).to_a
      ranked.last.update!(final_position: 1)
      ranked.first.update!(final_position: 2)
      @tournament.update_column(:state, :finished) # rubocop:disable Rails/SkipsModelValidations

      get play_standings_path(@tournament.slug)

      assert_select "[data-event-header] h1", text: "#{@tournament.name} · Final standings"
      assert_select "tbody tr" do |rows|
        assert_equal [ranked.last, ranked.first].map { |p| "event_participant_#{p.id}" }, rows.first(2).pluck("id")
      end
      assert_select "tbody tr:first-child [data-final-position]", text: "1"

      get play_standings_path(@tournament.slug, locale: "pt")
      assert_select "[data-event-header] h1", text: "#{@tournament.name} · Classificação final"
    end

    test "movement arrows: up, down, unchanged, and blank without a previous rank" do
      up, down, same, fresh = @tournament.event_participants.order(:created_at).first(4)
      { up => [3, 2], down => [1, 3], same => [2, 2], fresh => [nil, 4] }.each do |participant, ranks|
        ranks.each.with_index(1) do |rank, number|
          next unless rank

          @tournament.standings_snapshots.create!(round_number: number, event_participant: participant, rank: rank)
        end
      end

      get play_standings_path(@tournament.slug)

      assert_select "tr#event_participant_#{up.id} [data-movement]", text: /▲1/
      assert_select "tr#event_participant_#{up.id} [data-movement][title=?]", "Up 1 place since the last round"
      assert_select "tr#event_participant_#{down.id} [data-movement]", text: /▼2/
      assert_select "tr#event_participant_#{same.id} [data-movement]", text: /–/
      assert_select "tr#event_participant_#{fresh.id} [data-movement]", count: 0
      assert_select "p", text: "Small arrows: places moved since the last round."

      get tournament_event_participants_path(@tournament), headers: { "Turbo-Frame" => "modal" }
      assert_select "tr#event_participant_#{down.id} [data-movement]", text: /▼2/

      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
      get organizer_tournament_event_participants_path(@tournament)
      assert_select "tr#event_participant_#{up.id} [data-movement]", text: /▲1/
    end

    test "no arrows before two rounds have closed" do
      ::Standings::Snapshot.call(@tournament, @tournament.rounds.first)

      get play_standings_path(@tournament.slug)

      assert_select "[data-movement]", count: 0
    end
  end
end
