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
    read_filters
    @posts = feed_scope.recent.preload(:event, user: { avatar_attachment: :blob }).page(params[:page]).per(PER_PAGE)
    @liked_ids = marks(PostLike)
    @reported_ids = marks(PostReport)
    prepare_composer
  end

  def create
    @post = build_post

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

  # ?circuit= (one circuit's events), ?play= (one play pool) and ?event=, when they name real ones.
  def read_filters
    @circuit = Circuit.find_by(id: params[:circuit]) if params[:circuit].present?
    @play = params[:play].presence if Event::PLAYS.include?(params[:play].to_s)
    read_event_filter
  end

  def read_event_filter
    @events = posted_events.order(start_time: :desc).limit(60).to_a
    @event = @events.find { |event| event.id == params[:event] }
  end

  # Public events that have posts: the choices of the event filter.
  def posted_events
    Event.where(id: Post.select(:event_id)).where.not(state: Tournament.states.values_at(*Event::HIDDEN_STATES))
  end

  # "everyone" or "following" (signed-in only): ?scope= wins, else the account's choice.
  def feed_scope_param
    return "everyone" unless current_user

    scope = params[:scope].presence || current_user.feed_scope
    User::FEED_SCOPES.include?(scope) ? scope : "everyone"
  end

  # Visible posts, of one circuit's events when ?circuit= names one, narrowed to the people followed when asked.
  def feed_scope
    @scope = feed_scope_param
    scope = (@circuit ? Post.in_circuit(@circuit) : Post.all).visible
    scope = scope.about_play(@play) if @play
    scope = scope.where(event: @event) if @event
    @scope == "following" ? scope.followed_by(current_user) : scope
  end

  def prepare_composer
    @postable = Post.postable_events_for(current_user).limit(20).to_a
    @post = Post.new
  end

  # A thought has no event; about an event, the organizer writes notes and everyone else reports.
  def build_post
    post = Post.new(post_params.merge(user: current_user))
    post.kind = post.event ? kind_for(post.event) : "thought"
    post
  end

  def kind_for(event)
    event.event_organizer&.user_id == current_user.id ? "note" : "report"
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

  # A thought carries no event, whatever the form sent.
  def post_params
    attributes = params.expect(post: %i[event_id body kind])
    attributes[:kind] == "thought" ? { body: attributes[:body] } : attributes.slice(:event_id, :body)
  end
end
