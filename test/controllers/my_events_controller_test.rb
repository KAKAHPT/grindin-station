# frozen_string_literal: true

require "test_helper"

class MyEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @mine = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                    state: :registration_open)
    @other = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                     state: :registration_open)
    @user = User.create!(name: "Fresh Player", email_address: "fresh@example.com", password: "password123")
    Registrations::Enroll.call(event: @mine, player: @user.player)
  end

  test "a visitor is sent to sign in and has no menu link" do
    get my_events_path
    assert_redirected_to new_session_path

    get events_path
    assert_select ".topbar-links a[href=?]", my_events_path, count: 0
  end

  test "a player sees only the events they are registered in, with a link to each" do
    sign_in
    get my_events_path
    assert_response :success
    assert_select "[data-ticket-grid] a[href=?]", play_event_path(@mine.slug)
    assert_select "a[href=?]", play_event_path(@other.slug), count: 0
    assert_select "[data-ticket-grid] [data-register]", count: 0
    assert_select "[data-my-decklist]", text: I18n.t("my_events.add_decklist")
    assert_select "form[action=?] [data-my-drop]",
                  tournament_event_participant_path(@mine, @mine.event_participants.find_by!(player: @user.player))
    assert_select ".topbar-links a.on[href=?]", my_events_path, text: I18n.t("topbar.my_events")
  end

  test "the ticket shows the check-in, takes the decklist and comes back to the list" do
    @mine.update!(self_check_in_enabled: true, check_in_opens_hours_before: 1, start_time: 3.days.from_now,
                  end_time: 4.days.from_now)
    participant = @mine.event_participants.find_by!(player: @user.player)
    sign_in

    get my_events_path
    assert_select "[data-my-panel] [data-my-check-in=soon]"
    assert_select "[data-my-panel] form[data-my-decklist-form] input[name='event_participant[decklist]']"
    patch tournament_event_participant_path(@mine, participant),
          params: { from: "my_events", event_participant: { decklist: "https://moxfield.com/decks/abc" } }
    assert_redirected_to my_events_path
    assert_equal "https://moxfield.com/decks/abc", participant.reload.decklist

    @mine.update!(check_in_opens_hours_before: 100)
    get my_events_path
    assert_select "[data-my-panel] form[data-my-check-in=open]"
    patch check_in_tournament_event_participants_path(@mine), params: { from: "my_events" }
    assert_redirected_to my_events_path
    get my_events_path
    assert_select "[data-my-panel] [data-my-checked-in]"
    assert_select "[data-user-menu-panel] a[href=?]", my_events_path
  end

  test "a player added as staff finds the event with the way into its organizer side" do
    EventStaff.create!(event: @other, user: @user, role: "scorekeeper")
    sign_in

    get my_events_path
    assert_select "[data-my-staffed] [data-staffed-event='#{@other.id}']", text: /Scorekeeper/ do
      assert_select "a[href=?]", organizer_tournament_path(@other)
    end
    get organizer_tournament_path(@other)
    assert_response :success
  end

  test "events are sorted into running now, upcoming and past" do
    running = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :swiss)
    running.event_participants.first.update!(player: @user.player)
    @mine.update_columns(start_time: 3.days.ago, end_time: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    sign_in
    get my_events_path
    assert_select "h2", text: I18n.t("my_events.running")
    assert_select "details[data-my-past]:not([open]) summary", text: I18n.t("my_events.show_past", count: 1)
    assert_select "details[data-my-past] [data-ticket-grid]"
    assert_select "h2", text: I18n.t("my_events.upcoming"), count: 0
  end

  test "drop cancels the registration before the swiss and drops the player once it runs" do
    sign_in
    participant = @mine.event_participants.find_by!(player: @user.player)
    assert_difference -> { @mine.event_participants.count }, -1 do
      delete tournament_event_participant_path(@mine, participant)
    end

    running = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :swiss)
    seat = running.event_participants.first
    seat.update!(player: @user.player)
    get my_events_path
    assert_select "[data-my-drop]", count: 1
    assert_select "[data-my-decklist]", count: 0
    delete tournament_event_participant_path(running, seat)
    assert_predicate seat.reload, :dropped?
    get my_events_path
    assert_select "[data-my-dropped]"
    assert_select "[data-my-drop]", count: 0
  end

  test "a player with no events reads so and gets a link to the events" do
    @mine.event_participants.where(player: @user.player).destroy_all
    sign_in
    get my_events_path
    assert_select "[data-list-empty] a[href=?]", events_path
  end

  private

  def sign_in
    post session_path, params: { session: { email_address: @user.email_address, password: "password123" } }
  end
end
