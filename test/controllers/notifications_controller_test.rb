# frozen_string_literal: true

require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @round = @tournament.rounds.create!(type: SwissRound, number: 1, started_at: 1.hour.ago)
    @round.update!(published: true)
    @pod = @round.pods.order(:number).first
    @seats = @pod.event_participants.to_a
  end

  test "lists the user's notifications newest first, with a link to the subject" do
    call = JudgeCalls::Open.call(event: @tournament, pod: @pod, reason: "Rules question")
    older = users(:organizer_user).notifications.sole
    older.update!(created_at: 1.hour.ago)
    Notification.create!(user: users(:organizer_user), kind: "judge_call", subject: call)
    Notification.create!(user: users(:player_one), kind: "judge_call", subject: call)
    sign_in(users(:organizer_user))

    get notifications_path

    assert_response :success
    assert_select "[data-notification]", count: 2
    assert_select "[data-notification]:first-child[data-unread]"
    assert_select "[data-notification] a[href=?]", organizer_tournament_judge_calls_path(@tournament),
                  text: /A judge was called/
  end

  test "the notifications are one card with a title band" do
    sign_in(users(:player_one))

    get notifications_path

    assert_select "section.card > .card-title h1", text: "Notifications"
    assert_select "section.card p", text: "No notifications yet."
  end

  test "the table is told when a result is contested" do
    @tournament.update!(result_confirmation: "one")
    sign_in(@seats[0].player.user)
    post play_pod_report_path(@tournament.slug, @pod), params: { type: "Win", winner_id: @seats[0].id }
    sign_in(@seats[1].player.user)
    post play_pod_contest_path(@tournament.slug, @pod), params: { reason: "I won that game" }

    sign_in(@seats[2].player.user)
    get notifications_path

    assert_select "[data-notification] a[href=?]", play_me_path(@tournament.slug), text: /contested/
  end

  test "the unread count shows in the bell and clears when marked read" do
    user = @seats[0].player.user
    2.times { Notification.create!(user: user, kind: "result_contested") }
    sign_in(user)

    get play_me_path(@tournament.slug)
    assert_select "a[data-notifications-bell][href=?]", notifications_path, text: /2/
    assert_equal 2, user.unread_notifications_count

    post mark_all_read_notifications_path
    assert_redirected_to notifications_path
    assert_equal 0, user.unread_notifications_count

    get notifications_path
    assert_select "[data-notification][data-unread]", count: 0
  end

  test "the application layout shows the bell next to Account" do
    Notification.create!(user: users(:organizer_user), kind: "judge_call")
    sign_in(users(:organizer_user))

    get tournaments_path

    assert_select "a[data-notifications-bell][href=?]", notifications_path, text: /1/
  end

  test "requires a login" do
    get notifications_path

    assert_redirected_to new_session_path
  end

  private

  def sign_in(user)
    user.update!(password: "password123")
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
