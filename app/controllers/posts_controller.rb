# frozen_string_literal: true

# /feed: posts about finished events, newest first; signed-in players and organizers post about their events,
# like once, report once, and remove what is theirs (the event's organizer and admins too).
class PostsController < ApplicationController
  PER_PAGE = 20

  allow_unauthenticated_access only: :index
  layout "public"
  rate_limit to: 5, within: 10.minutes, only: :create, with: lambda {
    redirect_to feed_path, alert: t("flash.alert.try_again_later")
  }

  def index
    @circuit = Circuit.find_by(id: params[:circuit]) if params[:circuit].present?
    @posts = feed_scope.recent.preload(:event, user: { avatar_attachment: :blob }).page(params[:page]).per(PER_PAGE)
    @liked_ids = marks(PostLike)
    @reported_ids = marks(PostReport)
    prepare_composer
  end

  def create
    @post = Post.new(post_params.merge(user: current_user))
    @post.kind = kind_for(@post.event)

    if @post.save
      redirect_to feed_path, notice: t("feed.posted")
    else
      redirect_to feed_path, alert: @post.errors.full_messages.to_sentence
    end
  end

  def destroy
    post = Post.find(params.expect(:id))
    return redirect_to(feed_path, alert: t("flash.alert.not_allowed")) unless post.removable_by?(current_user)

    remove!(post)
    redirect_to feed_path, notice: t("feed.removed")
  end

  # Toggle: a second tap takes the like back.
  def like
    post = Post.find(params.expect(:id))
    like = post.post_likes.find_by(user: current_user)
    like ? like.destroy! : post.post_likes.create!(user: current_user)
    redirect_back_or_to(feed_path)
  end

  # One report per person, never on your own post; the third one hides the post for the admins to review.
  def report
    post = Post.find(params.expect(:id))
    post.post_reports.create!(user: current_user) if post.reportable_by?(current_user)
    redirect_back_or_to(feed_path, notice: t("feed.reported"))
  end

  private

  # Visible posts, of one circuit's events when ?circuit= names one.
  def feed_scope
    (@circuit ? Post.in_circuit(@circuit) : Post.all).visible
  end

  def prepare_composer
    @postable = Post.postable_events_for(current_user).limit(20).to_a
    @post = Post.new
  end

  # The event's organizer writes notes; everyone else reports.
  def kind_for(event)
    event&.event_organizer&.user_id == current_user.id ? "note" : "report"
  end

  def remove!(post)
    post.destroy!
    Audit.record("post_removed", subject: post.user, event: post.event, post_id: post.id, by: current_user.id)
  end

  # The ids of the listed posts the viewer has liked or reported.
  def marks(model)
    return Set.new unless current_user

    model.where(user: current_user, post_id: @posts.map(&:id)).pluck(:post_id).to_set
  end

  def post_params
    params.expect(post: %i[event_id body])
  end
end
