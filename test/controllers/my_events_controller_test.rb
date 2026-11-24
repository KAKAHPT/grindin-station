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
    assert_select ".topbar-links a.on[href=?]", my_events_path, text: I18n.t("topbar.my_events")
  end

  test "events are sorted into running now, upcoming and past" do
    running = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :swiss)
    running.event_participants.first.update!(player: @user.player)
    @mine.update_columns(start_time: 3.days.ago, end_time: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    sign_in
    get my_events_path
    assert_select "h2", text: I18n.t("my_events.running")
    assert_select "h2", text: I18n.t("my_events.past")
    assert_select "h2", text: I18n.t("my_events.upcoming"), count: 0
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
