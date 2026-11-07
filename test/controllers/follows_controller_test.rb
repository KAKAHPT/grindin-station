# frozen_string_literal: true

require "test_helper"

# Following people and the "Following" scope of the social feed.
class FollowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :finished)
    @me, @friend = @t.event_participants.first(2).map { |ep| ep.player.user }
    @me.update!(password: "password123")
    @friend.update!(handle: "ana-grind")
    @organizer = users(:organizer_user)
    @by_friend = Post.create!(user: @friend, event: @t, body: "Friend's report")
    @by_organizer = Post.create!(user: @organizer, event: @t, kind: "note", body: "Organizer's note")
    other_org = User.create!(name: "Other Org", email_address: "oo-#{SecureRandom.hex(3)}@example.com",
                             password: "password123", organizer: true)
    stranger_event = TournamentBuilder.build(players: 4, organizer: other_org.event_organizer, state: :finished)
    @by_stranger = Post.create!(user: stranger_event.event_participants.first.player.user, event: stranger_event,
                                body: "Stranger's report")
    sign_in(@me)
  end

  test "a hidden profile cannot be followed, so Follow does not reveal that the handle exists" do
    @friend.update!(visibility: "private")

    post follow_path("ana-grind")

    assert_response :not_found
    assert_not @me.reload.following?(@friend)
  end

  test "Follow/Unfollow on the profile; the Following scope keeps only followed people and organizers" do
    get profile_path("ana-grind")
    assert_select "[data-profile-follow] form button", text: "Follow"

    post follow_path("ana-grind")
    assert @me.reload.following?(@friend)
    get profile_path("ana-grind")
    assert_select "[data-profile-follow] form button", text: "Unfollow"

    get feed_path(scope: "following")
    assert_select "[data-feed-scope] a.seg-on", text: "Following"
    assert_select "[data-post='#{@by_friend.id}']"
    assert_select "[data-post='#{@by_organizer.id}']", count: 0
    assert_select "[data-post='#{@by_stranger.id}']", count: 0

    get organizer_profile_path(@organizer.handle)
    assert_select "[data-organizer-header] form button", text: "Follow"
    post follow_path(@organizer.handle)
    get feed_path(scope: "following")
    assert_select "[data-post='#{@by_organizer.id}']" # the organizer's own note
    assert_select "[data-post='#{@by_friend.id}']" # about the followed organizer's event, by a followed friend

    delete follow_path("ana-grind")
    assert_not @me.reload.following?(@friend)
    get feed_path(scope: "following")
    assert_select "[data-post='#{@by_friend.id}']" # still in: it is about the followed organizer's event
    assert_select "[data-post='#{@by_stranger.id}']", count: 0
  end

  test "the account choice sets the default scope; Everyone is the default and the only scope for visitors" do
    get feed_path
    assert_select "[data-feed-scope] a.seg-on", text: "Everyone"
    assert_select "[data-post='#{@by_stranger.id}']"

    patch account_path, params: { user: { feed_scope: "following" } }
    assert_equal "following", @me.reload.feed_scope
    get feed_path
    assert_select "[data-feed-scope] a.seg-on", text: "Following"
    assert_select "[data-feed-empty]", text: /people you follow/

    delete session_path
    get feed_path
    assert_select "[data-feed-scope]", count: 0
    assert_select "[data-post='#{@by_stranger.id}']"
    get profile_path("ana-grind")
    assert_select "[data-profile-follow] a[data-follow=sign_in][href=?]", new_session_path
  end

  test "you cannot follow yourself" do
    post follow_path(@me.handle)
    assert_equal 0, Follow.count
  end

  private

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
