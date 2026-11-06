# frozen_string_literal: true

require "test_helper"

# The feed: who can post about what, likes, removal, the result post at finish, and the circuit filter.
class PostsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  setup do
    @organizer = users(:organizer_user)
    @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :finished)
    @t.update_columns(circuit_id: circuits(:standard_circuit).id) # rubocop:disable Rails/SkipsModelValidations
    @player = @t.event_participants.first.player.user
    @player.update!(password: "password123")
  end

  test "a visitor reads the feed and the top bar links to it; posting needs a sign-in" do
    Post.create!(user: @organizer, event: @t, kind: "note", body: "Thanks everyone!")

    get feed_path
    assert_response :success
    assert_select "[data-topbar] nav a[href=?]", feed_path, text: "Social feed"
    assert_select "[data-post] [data-post-body]", text: "Thanks everyone!"
    assert_select "[data-feed-signin]"
    assert_select "[data-feed-composer]", count: 0
  end

  test "a player posts about a finished event they played, likes once, and removes their own post" do
    sign_in(@player)
    get feed_path
    assert_select "[data-feed-composer] select[name='post[event_id]'] option[value='#{@t.id}']"

    post feed_posts_path, params: { post: { event_id: @t.id, body: "Great tables, fair seats." } }
    assert_redirected_to feed_path
    created = Post.order(:created_at).last
    assert_equal ["report", @player.id], [created.kind, created.user_id]

    post like_feed_post_path(created)
    assert_equal 1, created.reload.likes_count
    post like_feed_post_path(created)
    assert_equal 0, created.reload.likes_count

    delete feed_post_path(created)
    assert_nil Post.find_by(id: created.id)
  end

  test "outsiders cannot post about the event; the organizer posts a note and can remove others' posts" do
    outsider = User.create!(name: "Outsider", email_address: "out-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
    sign_in(outsider)
    post feed_posts_path, params: { post: { event_id: @t.id, body: "I was not there." } }
    assert_equal 0, Post.count

    report = Post.create!(user: @player, event: @t, body: "Loved it")
    sign_in(@organizer)
    post feed_posts_path, params: { post: { event_id: @t.id, body: "Congrats to the winner!" } }
    assert_equal "note", Post.order(:created_at).last.kind
    delete feed_post_path(report)
    assert_nil Post.find_by(id: report.id)
    assert_equal "post_removed", AuditEvent.recent.first.action
  end

  test "finishing a tournament writes the result post once; the circuit page and ?circuit= show it" do
    Tournaments::FinishTournamentJob.perform_now(@t)
    Tournaments::FinishTournamentJob.perform_now(@t)
    result = Post.where(event: @t, kind: "result").sole
    assert_match(/won .* \(4 players\)/, result.body)

    get circuit_path(circuits(:standard_circuit))
    assert_select "[data-circuit-feed] [data-post='#{result.id}']"
    assert_operator response.body.index("data-ticket-grid"), :<, response.body.index("data-circuit-feed") # events first
    assert_select "[data-circuit-feed] a[data-circuit-feed-all][href=?]",
                  feed_path(circuit: circuits(:standard_circuit).id)

    get feed_path(circuit: circuits(:standard_circuit).id)
    assert_select "[data-feed-circuit]"
    assert_select "[data-post='#{result.id}'][data-post-kind=result]"
  end

  test "insults are refused; three reports hide a post until an admin keeps or removes it on /admin/feed" do
    sign_in(@player)
    post feed_posts_path, params: { post: { event_id: @t.id, body: "The judge is an asshole" } }
    assert_equal 0, Post.count
    assert_match(/not allowed/, flash[:alert])

    target = Post.create!(user: @player, event: @t, body: "Fine report")
    3.times do |i|
      reader = User.create!(name: "Reader #{i}", email_address: "r#{i}-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
      sign_in(reader)
      post report_feed_post_path(target)
      post report_feed_post_path(target) # a second report by the same person counts once
    end
    assert target.reload.hidden
    assert_equal 3, target.reports_count
    get feed_path
    assert_select "[data-post='#{target.id}']", count: 0

    @organizer.update_columns(admin: true) # rubocop:disable Rails/SkipsModelValidations
    sign_in(@organizer)
    get admin_feed_path
    assert_select "[data-reported-post='#{target.id}']"
    patch admin_keep_feed_path(target)
    assert_not target.reload.hidden
    assert_equal 0, target.reports_count
    get feed_path
    assert_select "[data-post='#{target.id}']"
  end

  test "a thought needs no event; @handle mentions link the profile and notify the person" do
    other = @t.event_participants.second.player.user
    other.update!(handle: "rita-grind", password: "password123")
    sign_in(@player)

    post feed_posts_path, params: { post: { kind: "thought", event_id: @t.id, body: "GG @rita-grind, that final!" } }
    thought = Post.order(:created_at).last
    assert_equal ["thought", nil], [thought.kind, thought.event_id]
    assert_equal 1, other.notifications.where(kind: "mentioned", subject: thought).count

    get feed_path
    assert_select "[data-post='#{thought.id}'] [data-post-body] a[href=?]", profile_path("rita-grind"),
                  text: "@rita-grind"
    assert_select "[data-feed-composers] [data-feed-composer=thought]"

    sign_in(other)
    get notifications_path
    assert_select "[data-notification] a[href=?]", feed_path, text: /mentioned you/
  end

  private

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
