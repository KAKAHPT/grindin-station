# frozen_string_literal: true

require "test_helper"

module Organizer
  # The day roster: check-in, payment, drops, no-shows, waitlist and late registration.
  class RosterTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                            state: :registration_closed)
      @participant = @tournament.event_participants.first
      @users =
        %w[organizer judge scorekeeper].index_with do |role|
          user = User.create!(name: role, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                              password: "password123")
          EventStaff.create!(event: @tournament, user: user, role: role)
          user
        end
    end

    test "a scorekeeper checks a player in and out and marks them paid" do
      sign_in_as("scorekeeper")

      patch check_in_organizer_tournament_event_participant_path(@tournament, @participant)
      assert_redirected_to organizer_tournament_event_participants_path(@tournament, layout: "application")
      @participant.reload
      assert @participant.checked_in?
      assert_not_nil @participant.checked_in_at

      patch mark_paid_organizer_tournament_event_participant_path(@tournament, @participant)
      assert @participant.reload.paid?

      patch undo_check_in_organizer_tournament_event_participant_path(@tournament, @participant)
      @participant.reload
      assert_not @participant.checked_in?
      assert_nil @participant.checked_in_at

      patch mark_unpaid_organizer_tournament_event_participant_path(@tournament, @participant)
      assert_not @participant.reload.paid?
    end

    test "scorekeepers cannot drop or promote; judges can" do
      sign_in_as("scorekeeper")
      patch drop_organizer_tournament_event_participant_path(@tournament, @participant), params: { reason: "no_show" }
      assert_refused
      patch promote_organizer_tournament_event_participant_path(@tournament, @participant)
      assert_refused
      assert_not @participant.reload.dropped?

      sign_in_as("judge")
      patch drop_organizer_tournament_event_participant_path(@tournament, @participant), params: { reason: "no_show" }
      assert @participant.reload.dropped?
    end

    test "an organizer records a no-show and promotes from the waitlist before the swiss" do
      waiting = @tournament.event_participants.second
      waiting.update!(waitlisted: true, waitlist_position: 1)
      sign_in_as("organizer")

      patch drop_organizer_tournament_event_participant_path(@tournament, @participant), params: { reason: "no_show" }
      assert_equal "no_show", @participant.reload.drop_reason
      assert @participant.dropped?
      assert_not waiting.reload.waitlisted?, "the drop promotes the first on the waitlist"

      waiting.update!(waitlisted: true, waitlist_position: 1)
      patch promote_organizer_tournament_event_participant_path(@tournament, waiting)
      assert_not waiting.reload.waitlisted?
      assert_nil waiting.waitlist_position
    end

    test "promotion is refused once the swiss started" do
      waiting = @tournament.event_participants.second
      waiting.update!(waitlisted: true, waitlist_position: 1)
      @tournament.update_column(:state, "swiss") # rubocop:disable Rails/SkipsModelValidations
      sign_in_as("organizer")

      patch promote_organizer_tournament_event_participant_path(@tournament, waiting)
      assert waiting.reload.waitlisted?
      assert_equal I18n.t("flash.alert.registration_closed"), flash[:alert]
    end

    test "counters and the status filter" do
      participants = @tournament.event_participants.order(:id).to_a
      participants[0].update!(checked_in: true)
      participants[1].update!(dropped: true, drop_reason: "drop")
      participants[2].update!(waitlisted: true, waitlist_position: 1)
      sign_in_as("scorekeeper")

      get organizer_tournament_event_participants_path(@tournament, layout: "application")
      assert_response :success
      assert_select "#roster_count_enrolled", "2"
      assert_select "#roster_count_checked_in", "1"
      assert_select "#roster_count_waitlisted", "1"
      assert_select "#roster_count_dropped", "1"

      get organizer_tournament_event_participants_path(@tournament, layout: "application", status: "waitlisted")
      assert_select "tbody tr[id^=event_participant_]", 0
      assert_select "[data-waitlist] [data-waitlist-row='#{participants[2].id}']"
      assert_select "[data-waitlist] form", 0, "a scorekeeper neither promotes nor removes"

      get organizer_tournament_event_participants_path(@tournament, layout: "application", status: "checked_in")
      assert_select "tbody tr[id^=event_participant_]", 1
      assert_select "tbody tr##{ActionView::RecordIdentifier.dom_id(participants[0])}"
    end

    test "the organizer cannot add players once the swiss started" do
      @tournament.update_column(:state, "swiss") # rubocop:disable Rails/SkipsModelValidations
      sign_in_as("organizer")

      assert_no_difference -> { EventParticipant.count } do
        post organizer_tournament_event_participants_path(@tournament),
             params: { event_participant: { player_name: "Late", player_email: "late@example.com",
                                            accepted_terms: "1" } }
      end
      assert_equal I18n.t("flash.alert.registration_closed"), flash[:alert]
    end

    test "public registration is closed once the swiss started" do
      @tournament.update_column(:state, "swiss") # rubocop:disable Rails/SkipsModelValidations
      sign_in_user(users(:player_one))

      get new_tournament_event_participant_path(@tournament)
      assert_redirected_to tournament_path(@tournament)
      assert_equal I18n.t("flash.alert.registration_closed"), flash[:alert]

      assert_no_difference -> { EventParticipant.count } do
        post tournament_event_participants_path(@tournament),
             params: { event_participant: { accepted_terms: "1" } }
      end
      assert_equal I18n.t("flash.alert.registration_closed"), flash[:alert]
    end

    test "public registration goes to the waitlist when full, or is refused without one" do
      @tournament.update_column(:state, Tournament.states[:registration_open]) # rubocop:disable Rails/SkipsModelValidations
      @tournament.update!(maximum_participants: 4)
      sign_in_user(users(:player_one))

      post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
      assert_equal I18n.t("flash.alert.registration_full"), flash[:alert]

      @tournament.update!(waitlist_enabled: true)
      post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
      assert_redirected_to tournament_path(@tournament)
      assert_equal I18n.t("flash.notice.registration_waitlisted", position: 1), flash[:notice]
      assert @tournament.event_participants.find_by(player: players(:player_one)).waitlisted?
    end

    test "public registration still requires the terms" do
      @tournament.update_column(:state, "registration_open") # rubocop:disable Rails/SkipsModelValidations
      sign_in_user(users(:player_one))

      assert_no_difference -> { EventParticipant.count } do
        post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "0" } }
      end
      assert_redirected_to @tournament
      assert flash[:alert].present?
    end

    test "an enrolled player cancelling before the swiss lets the first on the waitlist in" do
      first, second = waitlist_players
      leaving = @tournament.event_participants.enrolled.first
      leaving.player.user.update!(password: "password123")
      sign_in_user(leaving.player.user)

      assert_difference -> { EventParticipant.count }, -1 do
        delete tournament_event_participant_path(@tournament, leaving)
      end
      assert_redirected_to tournament_path(@tournament)
      assert_not first.reload.waitlisted?
      assert_equal 1, second.reload.waitlist_position
    end

    test "a waitlisted player cancelling promotes no one and closes the gap" do
      first, second = waitlist_players
      sign_in_user(users(:player_one))

      delete tournament_event_participant_path(@tournament, first)

      assert_not EventParticipant.exists?(first.id)
      assert second.reload.waitlisted?
      assert_equal 1, second.waitlist_position
      assert_equal 4, @tournament.reload.playing_participants_count
    end

    test "cancelling after the swiss started is a drop" do
      @tournament.update_column(:state, "swiss") # rubocop:disable Rails/SkipsModelValidations
      leaving = @tournament.event_participants.first
      leaving.player.user.update!(password: "password123")
      sign_in_user(leaving.player.user)

      assert_no_difference -> { EventParticipant.count } do
        delete tournament_event_participant_path(@tournament, leaving)
      end
      leaving.reload
      assert leaving.dropped?
      assert_equal "drop", leaving.drop_reason
    end

    private

    # Fills the 4-player event and puts players one and two on its waitlist.
    def waitlist_players
      @tournament.update_column(:state, "registration_open") # rubocop:disable Rails/SkipsModelValidations
      @tournament.reload.update!(maximum_participants: 4, waitlist_enabled: true)
      %i[player_one player_two].map { |name| Registrations::Enroll.call(event: @tournament, player: players(name)) }
    end

    def assert_refused
      assert_redirected_to organizer_root_path
      assert_equal I18n.t("flash.alert.not_allowed"), flash[:alert]
    end

    def sign_in_as(role)
      sign_in_user(@users.fetch(role))
    end

    def sign_in_user(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
