# frozen_string_literal: true

require "test_helper"

module Play
  class TablesTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: SwissRound, number: 1)
      @round.update!(published: true)
      @pod = @round.pods.order(:number).first
      @seats = @pod.event_participants.to_a
      @me = @seats[1]
    end

    test "a participant sees their table and seat, marked as You" do
      sign_in(@me)
      get play_me_path(@tournament.slug)

      assert_response :success
      assert_select "[data-table-number]", text: /#{@pod.number}/
      assert_select "[data-seat-number]", text: /2/
      assert_select "li[data-me]", text: /#{@me.name}.*You/m
      @seats.each { |seat| assert_includes response.body, seat.name }
      assert_select "a", text: "Report result"
      assert_select "button", text: "Call a judge"
      assert_select "nav[data-play-nav]"
    end

    test "the header links the player's own name to a public profile only" do
      user = @me.player.user
      sign_in(@me)

      get play_me_path(@tournament.slug)
      assert_select "[data-play-player] a[href=?]", profile_path(user.handle), text: user.name

      user.update!(visibility: "private")
      get play_me_path(@tournament.slug)
      assert_select "[data-play-player] a", count: 0
      assert_select "[data-play-player]", text: user.name
    end

    test "commanders show only when the event allows it" do
      @me.update!(decklist: "Kinnan, Bonder Prodigy")
      sign_in(@me)

      get play_me_path(@tournament.slug)
      assert_not_includes response.body, "Kinnan, Bonder Prodigy"

      @tournament.update!(show_commanders_in_standings: true)
      get play_me_path(@tournament.slug)
      assert_includes response.body, "Kinnan, Bonder Prodigy"
    end

    test "someone not in the event is redirected" do
      outsider = User.create!(name: "Outsider", email_address: "out-#{SecureRandom.hex(3)}@example.com",
                              password: "password123")
      post session_path, params: { session: { email_address: outsider.email_address, password: "password123" } }

      get play_me_path(@tournament.slug)

      assert_redirected_to tournament_path(@tournament)
      assert_equal I18n.t("play.not_a_participant"), flash[:alert]
    end

    test "a dropped participant is redirected" do
      sign_in(@me)
      @me.update_column(:dropped, true) # rubocop:disable Rails/SkipsModelValidations

      get play_me_path(@tournament.slug)

      assert_redirected_to tournament_path(@tournament)
    end

    test "logged out goes to the sign-in page" do
      get play_me_path(@tournament.slug)

      assert_redirected_to new_session_path
    end

    test "without a published round the player waits for pairings" do
      @round.update!(published: false)
      sign_in(@me)

      get play_me_path(@tournament.slug)

      assert_response :success
      assert_includes response.body, "Waiting for pairings"
    end

    test "a player without a seat this round has a bye" do
      sign_in(@me)
      Seating.where(pod: @pod, event_participant: @me).delete_all

      get play_me_path(@tournament.slug)

      assert_response :success
      assert_includes response.body, "You have a bye this round"
    end

    test "the page renders in Portuguese, with Draw kept in English" do
      sign_in(@me)

      get play_me_path(@tournament.slug, locale: "pt")

      assert_response :success
      assert_select "html[lang=pt]"
      assert_select "a", text: "Reportar resultado"
      assert_select "button", text: "Chamar um juiz"

      get play_pod_report_new_path(@tournament.slug, @pod, locale: "pt")
      assert_response :success
      assert_select "button", text: "Draw"
    end

    test "a player of another event cannot open this event's pages" do
      other = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      sign_in(other.event_participants.first)

      get play_me_path(@tournament.slug)

      assert_redirected_to tournament_path(@tournament)
    end

    private

    def sign_in(participant)
      user = participant.player.user
      user.update!(password: "password123")
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
