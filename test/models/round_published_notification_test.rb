# frozen_string_literal: true

require "test_helper"

# Publishing a round tells every seated player with an account, once.
class RoundPublishedNotificationTest < ActionDispatch::IntegrationTest
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @user = users(:player_one)
    @tournament.event_participants.first.update!(player: @user.player)
    @round = @tournament.rounds.create!(type: SwissRound, number: 1)
  end

  test "each seated player gets one notification when the round is published, none before or again" do
    assert_equal 0, Notification.where(kind: "round_published").count

    @round.update!(published: true)
    users = @round.pods.flat_map { |pod| pod.users.to_a }
    assert_equal 8, users.size
    assert_equal users.map(&:id).sort, Notification.where(kind: "round_published", subject: @round).pluck(:user_id).sort

    assert_no_difference -> { Notification.count } do
      @round.update!(started_at: Time.current)
    end
  end

  test "the notification names the round and the event and leads to the player's table" do
    @round.update!(published: true)
    post session_path, params: { session: { email_address: @user.email_address, password: "password123" } }
    get notifications_path
    assert_select "a[href=?]", play_me_path(@tournament.slug),
                  text: "Round #1 of #{@tournament.name} is out. See your table."
  end
end
