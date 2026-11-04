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

    test "a visitor sees the event header, the About card and the counts, but no player names" do
      get play_event_path(@tournament.slug)

      assert_response :success
      assert_select ".evhead", count: 1
      assert_select "[data-event-header] h1", text: @tournament.name
      assert_select ".evhead-eyebrow", text: "Sold out · cEDH · pods of four"
      assert_select ".evhead-line", text: /Lisboa · 4 players/
      assert_select "[data-event-header] nav.seg a.seg-on[aria-current=page]", text: "Event"
      assert_select "[data-about] .markdown strong", text: "Bring sleeves"
      assert_includes response.body, "Rua do Grind 1, Lisboa"
      assert_select "a[href^='https://www.google.com/maps']"
      assert_select "[data-event-price]", text: /10,00 €/
      assert_select "[data-registration] [data-counters]", text: /4 players enrolled.*2 on the waiting list/m
      assert_select "[data-enrolled], [data-waitlist]", count: 0
      (@enrolled + @waiting).each { |participant| assert_not_includes response.body, participant.name }
      assert_select "[data-you]", count: 0
    end

    test "never shows anyone's decklist or commander, even with commanders on" do
      @tournament.update!(show_commanders_in_standings: true)

      get play_event_path(@tournament.slug)

      assert_not_includes response.body, "Kinnan, Bonder Prodigy"
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

      assert_select "[data-registration] a[href=?]", new_session_path, text: "Sign in to register"
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
        assert_select "button", text: "Join waiting list"
      end
      assert_select "button", text: "Cancel registration", count: 0

      post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
      follow_redirect!
      assert_redirected_to play_event_path(@tournament.slug)
      follow_redirect!
      assert_select "[data-flash=notice]", text: /waitlist/i
      assert_select "[data-you] [data-you-state]", text: "Waiting list #3"
    end

    test "an enrolled player sees the You card: chips, own decklist form, cancel and My table" do
      me = @enrolled.first
      me.update!(checked_in: true)
      sign_in_user(me.player.user)

      get play_event_path(@tournament.slug)

      assert_select "[data-registration]", count: 0
      assert_select "[data-you]" do
        assert_select "[data-you-state]", text: "You are enrolled"
        assert_select "[data-checked-in]", text: "Checked in"
        assert_select "form[data-decklist-form][action=?]", tournament_event_participant_path(@tournament, me) do
          assert_select "input[name=_method][value=patch]"
          assert_select "input[name='event_participant[decklist]'][value=?]", "Kinnan, Bonder Prodigy"
          assert_select "button", text: "Save"
        end
        assert_select "form[action=?]", tournament_event_participant_path(@tournament, me) do
          assert_select "input[name=_method][value=delete]"
          assert_select "button[data-turbo-confirm]", text: "Cancel registration"
        end
      end
      (@enrolled - [me]).each { |participant| assert_not_includes response.body, participant.name }
      assert_select "button", text: "Register", count: 0
      assert_select "nav[data-play-nav] a[href=?]", play_me_path(@tournament.slug), text: "My table"
      assert_select "[data-play-header-nav] a[href=?]", play_me_path(@tournament.slug), text: "My table"
    end

    test "the player saves their decklist from the You card until round 1 is published, then it is read-only" do
      me = @enrolled.first
      sign_in_user(me.player.user)

      patch tournament_event_participant_path(@tournament, me),
            params: { event_participant: { decklist: "https://moxfield.com/decks/mine" } }
      assert_equal "https://moxfield.com/decks/mine", me.reload.decklist

      @tournament.update_column(:state, :swiss) # rubocop:disable Rails/SkipsModelValidations
      @tournament.rounds.create!(type: SwissRound, number: 1).update!(published: true)
      get play_event_path(@tournament.slug)

      assert_select "[data-you]" do
        assert_select "form[data-decklist-form]", count: 0
        assert_select "input[data-decklist-locked][readonly][value=?]", "https://moxfield.com/decks/mine"
        assert_select "p", text: /locked/
      end

      patch tournament_event_participant_path(@tournament, me), params: { event_participant: { decklist: "x" } }
      assert_equal "https://moxfield.com/decks/mine", me.reload.decklist
    end

    test "a waitlisted player can cancel but has no table" do
      sign_in_user(@waiting.first.player.user)

      get play_event_path(@tournament.slug)

      assert_select "[data-you] [data-you-state]", text: "Waiting list #1"
      assert_select "button", text: "Cancel registration"
      assert_select "nav[data-play-nav] a", text: "My table", count: 0
      assert_select "[data-play-header-nav] a", text: "My table", count: 0
    end

    test "the organizer gets a Manage link" do
      sign_in_user(users(:organizer_user))

      get play_event_path(@tournament.slug)

      assert_select "a[href=?]", organizer_tournament_path(@tournament), text: "Manage"
      assert_select "[data-registration] [data-counters]", text: /4 players enrolled/
      assert_select "[data-enrolled], [data-waitlist]", count: 0
    end

    test "a sold-out event says so and offers the waiting list; with a free place it is Registration open" do
      sign_in_user(User.create!(name: "Late", email_address: "late-#{SecureRandom.hex(3)}@example.com",
                                password: "password123"))

      get play_event_path(@tournament.slug)
      assert_select ".evhead-eyebrow", text: "Sold out · cEDH · pods of four"
      assert_select "[data-registration] .text-warn", text: /waiting list/
      assert_select "[data-registration] button", text: "Join waiting list"

      get play_event_path(@tournament.slug, locale: "pt")
      assert_select ".evhead-eyebrow", text: /\AEsgotado · /
      assert_select "[data-registration] button", text: "Entrar na lista de espera"

      @tournament.update!(maximum_participants: 8)
      get play_event_path(@tournament.slug, locale: "en")
      assert_select ".evhead-eyebrow", text: "Registration open · cEDH · pods of four"
      assert_select "[data-registration] button", text: "Register"
    end

    test "a sold-out event without a waiting list shows Registration is full and no enrol form" do
      @waiting.each(&:destroy!)
      @tournament.update!(waitlist_enabled: false)
      sign_in_user(User.create!(name: "Shut Out", email_address: "shut-#{SecureRandom.hex(3)}@example.com",
                                password: "password123"))

      get play_event_path(@tournament.slug)

      assert_select ".evhead-eyebrow", text: "Sold out · cEDH · pods of four"
      assert_select "[data-registration] [data-full]", text: "Registration is full."
      assert_select "[data-registration] [data-counters]", text: "4 players enrolled."
      assert_select "[data-registration] form", count: 0
      assert_select "[data-registration] button", count: 0
    end

    test "the state chip follows the event" do
      @tournament.update_column(:state, :swiss) # rubocop:disable Rails/SkipsModelValidations
      round = @tournament.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true)
      get play_event_path(@tournament.slug)
      assert_select ".evhead-eyebrow", text: "Swiss round 1 · cEDH · pods of four"

      round.update!(started_at: Time.current)
      get play_event_path(@tournament.slug)
      assert_select ".evhead-eyebrow", text: "Swiss round 1 · cEDH · pods of four · live"

      @tournament.update_columns(state: :single_elimination, top_cut_size: 16) # rubocop:disable Rails/SkipsModelValidations
      get play_event_path(@tournament.slug)
      assert_select ".evhead-eyebrow", text: /\ATop 16 · /

      @tournament.update_column(:state, :finished) # rubocop:disable Rails/SkipsModelValidations
      get play_event_path(@tournament.slug, locale: "pt")
      assert_select ".evhead-eyebrow", text: /\ATerminado · cEDH · mesas de quatro/
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
