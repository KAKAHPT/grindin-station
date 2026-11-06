# frozen_string_literal: true

require "test_helper"

module Play
  # M16: players check themselves in from the event page inside the window; decklists optional unless required.
  class SelfCheckInTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                            state: :registration_open)
      @tournament.update!(start_time: Time.zone.local(2026, 11, 7, 14, 0), check_in_opens_hours_before: 3,
                          end_time: Time.zone.local(2026, 11, 7, 22, 0))
      @me = @tournament.event_participants.order(:created_at).first
      sign_in_as(@me.player.user)
    end

    test "inside the window the You card offers Check in and the player is checked in" do
      travel_to Time.zone.local(2026, 11, 7, 11, 30) do
        get play_event_path(@tournament.slug)
        assert_response :success
        assert_select "[data-you] form[data-check-in] button", text: "Check in"

        patch check_in_tournament_event_participants_path(@tournament)

        assert_redirected_to @tournament
        assert_equal I18n.t("flash.notice.checked_in"), flash[:notice]
        assert @me.reload.checked_in?
        assert_in_delta Time.current, @me.checked_in_at, 1

        get play_event_path(@tournament.slug)
        assert_select "[data-you] [data-checked-in]", count: 1
        assert_select "[data-you] form[data-check-in]", count: 0
      end
    end

    test "before the window the card says when check-in opens and the request is refused" do
      travel_to Time.zone.local(2026, 11, 7, 9, 0) do
        get play_event_path(@tournament.slug)
        assert_select "[data-you] form[data-check-in]", count: 0
        assert_select "[data-you] [data-check-in-opens]", text: /11:00/

        patch check_in_tournament_event_participants_path(@tournament)

        assert_redirected_to @tournament
        assert_equal I18n.t("flash.alert.check_in_closed"), flash[:alert]
        assert_not @me.reload.checked_in?
      end
    end

    test "with self check-in off nothing is offered and the request is refused" do
      @tournament.update!(self_check_in_enabled: false)
      travel_to Time.zone.local(2026, 11, 7, 13, 0) do
        get play_event_path(@tournament.slug)
        assert_select "[data-you] form[data-check-in]", count: 0
        assert_select "[data-you] [data-check-in-opens]", count: 0

        patch check_in_tournament_event_participants_path(@tournament)
        assert_equal I18n.t("flash.alert.check_in_closed"), flash[:alert]
        assert_not @me.reload.checked_in?
      end
    end

    test "a waitlisted player cannot check in" do
      @me.update!(waitlisted: true, waitlist_position: 1)
      travel_to Time.zone.local(2026, 11, 7, 13, 0) do
        get play_event_path(@tournament.slug)
        assert_select "[data-you] form[data-check-in]", count: 0

        patch check_in_tournament_event_participants_path(@tournament)
        assert_equal I18n.t("flash.alert.check_in_closed"), flash[:alert]
        assert_not @me.reload.checked_in?
      end
    end

    test "the decklist is optional at registration unless the organizer requires it" do
      other = User.create!(name: "Newcomer", email_address: "newcomer-#{SecureRandom.hex(3)}@example.com",
                           password: "password123")
      @tournament.update!(maximum_participants: 8)
      sign_in_as(other)

      post tournament_event_participants_path(@tournament),
           params: { event_participant: { accepted_terms: "1", decklist: "" } }
      assert_redirected_to @tournament
      player = other.player
      assert @tournament.event_participants.exists?(player: player)

      @tournament.event_participants.find_by!(player: player).destroy
      @tournament.update!(decklist_required: true)
      post tournament_event_participants_path(@tournament),
           params: { event_participant: { accepted_terms: "1", decklist: "" } }
      assert_redirected_to @tournament
      assert_equal I18n.t("flash.alert.decklist_required"), flash[:alert]
      assert_not @tournament.event_participants.exists?(player: player)

      post tournament_event_participants_path(@tournament),
           params: { event_participant: { accepted_terms: "1", decklist: "https://moxfield.com/decks/abc" } }
      assert_redirected_to @tournament
      assert @tournament.event_participants.exists?(player: player)
    end

    test "the player edits the decklist until the swiss starts, then it is locked" do
      patch tournament_event_participant_path(@tournament, @me), params: { event_participant: { decklist: "Kinnan" } }
      assert_equal "Kinnan", @me.reload.decklist

      @tournament.update!(state: :registration_closed)
      patch tournament_event_participant_path(@tournament, @me), params: { event_participant: { decklist: "Tymna" } }
      assert_equal "Tymna", @me.reload.decklist

      @tournament.update_column(:state, Tournament.states[:swiss]) # rubocop:disable Rails/SkipsModelValidations
      patch tournament_event_participant_path(@tournament, @me), params: { event_participant: { decklist: "Sisay" } }
      assert_equal I18n.t("flash.alert.decklist_locked"), flash[:alert]
      assert_equal "Tymna", @me.reload.decklist
      get play_event_path(@tournament.slug)
      assert_select "[data-you] [data-decklist-locked]", count: 1
    end

    private

    def sign_in_as(user)
      user.update!(password: "password123")
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
