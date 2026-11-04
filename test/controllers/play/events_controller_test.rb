# frozen_string_literal: true

require "test_helper"

module Play
  class EventsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                            state: :registration_open)
      @tournament.update!(waitlist_enabled: true, maximum_participants: 4, description: "**Bring sleeves**",
                          address: "Rua do Grind 1, Lisboa", price: 10, currency: :euro)
      @enrolled = @tournament.event_participants.order(:created_at).to_a
      @enrolled.first.update!(decklist: "Kinnan, Bonder Prodigy")
      @waiting = Array.new(2) { |i| waitlist!(i + 1) }
    end

    test "a visitor sees the event, the enrolled players and the waitlist with positions" do
      get play_event_path(@tournament.slug)

      assert_response :success
      assert_select "h1", text: @tournament.name
      assert_select "[data-event-state]", text: "Registration open"
      assert_select ".markdown strong", text: "Bring sleeves"
      assert_includes response.body, "Rua do Grind 1, Lisboa"
      assert_select "a[href^='https://www.google.com/maps']"
      assert_select "[data-event-price]", text: /10,00 €/
      assert_select "[data-enrolled] li", count: 4
      @enrolled.each { |participant| assert_select "[data-enrolled]", text: /#{participant.name}/ }
      assert_select "[data-waitlist] li", count: 2
      assert_select "[data-waitlist] li", text: /1.*#{@waiting[0].name}/m
      assert_select "[data-waitlist] li", text: /2.*#{@waiting[1].name}/m
      assert_select "[data-counters]", text: %r{4\s*/\s*4}
    end

    test "never shows decklists, and commanders only when the event allows it" do
      get play_event_path(@tournament.slug)
      assert_not_includes response.body, "Kinnan, Bonder Prodigy"

      @tournament.update!(show_commanders_in_standings: true)
      get play_event_path(@tournament.slug)
      assert_includes response.body, "Kinnan, Bonder Prodigy"
    end

    test "a decklist that is a web address never shows, even with commanders on" do
      @tournament.update!(show_commanders_in_standings: true)
      @enrolled.first.update!(decklist: "https://moxfield.com/decks/secret")

      get play_event_path(@tournament.slug)

      assert_response :success
      assert_not_includes response.body, "moxfield.com"
    end

    test "a visitor is asked to sign in to enrol and gets no player items" do
      get play_event_path(@tournament.slug)

      assert_select "a[href=?]", new_session_path, text: "Sign in to enrol"
      assert_select "nav[data-play-nav] a", text: "My table", count: 0
      assert_select "nav[data-play-nav] a", text: "Event"
      assert_select "nav[data-play-nav] a", text: "Standings"
      assert_select "[data-play-player]", count: 0
    end

    test "a signed-in player not enrolled can enrol" do
      outsider = User.create!(name: "Outsider", email_address: "out-#{SecureRandom.hex(3)}@example.com",
                              password: "password123")
      sign_in_user(outsider)

      get play_event_path(@tournament.slug)

      assert_select "form[action=?][method=post]", tournament_event_participants_path(@tournament) do
        assert_select "input[type=checkbox][name='event_participant[accepted_terms]'][required]"
        assert_select "button", text: "Enrol"
      end
      assert_select "button", text: "Cancel registration", count: 0

      post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
      follow_redirect!
      assert_redirected_to play_event_path(@tournament.slug)
      follow_redirect!
      assert_select "[data-flash=notice]", text: /waitlist/i
      assert_select "[data-waitlist] li", text: /3.*Outsider/m
    end

    test "an enrolled player can cancel and sees My table" do
      sign_in_user(@enrolled.last.player.user)

      get play_event_path(@tournament.slug)

      assert_select "form[action=?]", tournament_event_participant_path(@tournament, @enrolled.last) do
        assert_select "input[name=_method][value=delete]"
        assert_select "button[data-turbo-confirm]", text: "Cancel registration"
      end
      assert_select "button", text: "Enrol", count: 0
      assert_select "nav[data-play-nav] a[href=?]", play_me_path(@tournament.slug), text: "My table"
    end

    test "a waitlisted player can cancel but has no table" do
      sign_in_user(@waiting.first.player.user)

      get play_event_path(@tournament.slug)

      assert_select "button", text: "Cancel registration"
      assert_select "nav[data-play-nav] a", text: "My table", count: 0
    end

    test "the organizer gets a Manage link" do
      sign_in_user(users(:organizer_user))

      get play_event_path(@tournament.slug)

      assert_select "a[href=?]", organizer_tournament_path(@tournament), text: "Manage"
    end

    test "the state chip follows the event" do
      @tournament.update_column(:state, :swiss) # rubocop:disable Rails/SkipsModelValidations
      round = @tournament.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true)
      get play_event_path(@tournament.slug)
      assert_select "[data-event-state]", text: "Swiss round 1"

      @tournament.update_columns(state: :single_elimination, top_cut_size: 16) # rubocop:disable Rails/SkipsModelValidations
      get play_event_path(@tournament.slug)
      assert_select "[data-event-state]", text: "Top 16"

      @tournament.update_column(:state, :finished) # rubocop:disable Rails/SkipsModelValidations
      get play_event_path(@tournament.slug, locale: "pt")
      assert_select "[data-event-state]", text: "Terminado"
    end

    test "the old event address redirects to the public page" do
      get tournament_path(@tournament)

      assert_redirected_to play_event_path(@tournament.slug)
    end

    test "an unknown slug is not found" do
      get play_event_path("no-such-event")

      assert_response :not_found
    end

    test "the event header shows the cover, loaded with the event (one attachment and one blob query)" do
      @tournament.cover.attach(io: Rails.root.join("test/fixtures/files/cover1.jpg").open, filename: "cover1.jpg",
                               content_type: "image/jpeg")
      queries = []
      count = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("active_storage") }
      ActiveSupport::Notifications.subscribed(count, "sql.active_record") { get play_event_path(@tournament.slug) }

      assert_response :success
      assert_select "[data-event-header] .evhead-ban[style*='cover1.jpg']"
      assert_equal 1, queries.count { |sql|
        sql.start_with?(%(SELECT "active_storage_attachments"))
      }, queries.join("\n")
      assert_equal 1, queries.count { |sql| sql.start_with?(%(SELECT "active_storage_blobs")) }, queries.join("\n")
    end

    private

    def waitlist!(position)
      user = User.create!(name: "Waiting #{position}", password: "password123",
                          email_address: "wait-#{position}-#{SecureRandom.hex(3)}@example.com")
      @tournament.event_participants.create!(player: user.player, accepted_terms: true, waitlisted: true,
                                             waitlist_position: position)
    end

    def sign_in_user(user)
      user.update!(password: "password123")
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
