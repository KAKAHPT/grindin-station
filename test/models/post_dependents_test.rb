# frozen_string_literal: true

require "test_helper"

# Deleting an event or a user takes its social posts (and their likes and reports) along instead of
# tripping the foreign keys.
class PostDependentsTest < ActiveSupport::TestCase
  setup do
    @event = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :finished)
    @organizer = users(:organizer_user)
    @player = @event.event_participants.first.player.user
  end

  test "destroying an event removes its posts, likes and reports" do
    post = Post.create!(user: @organizer, event: @event, kind: "note", body: "Thanks everyone!")
    PostLike.create!(post: post, user: @player)
    PostReport.create!(post: post, user: @player)

    assert_difference -> { Post.count } => -1, -> { PostLike.count } => -1, -> { PostReport.count } => -1 do
      @event.destroy!
    end
  end

  test "destroying a user removes their posts, likes and reports" do
    post = Post.create!(user: @organizer, event: @event, kind: "note", body: "Thanks everyone!")
    Post.create!(user: @player, kind: "thought", body: "Great weekend")
    PostLike.create!(post: post, user: @player)
    PostReport.create!(post: post, user: @player)

    assert_difference -> { Post.count } => -1, -> { PostLike.count } => -1, -> { PostReport.count } => -1 do
      @player.destroy!
    end
  end
end
