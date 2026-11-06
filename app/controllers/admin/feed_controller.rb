# frozen_string_literal: true

module Admin
  # /admin/feed: reported or hidden posts; Keep clears the reports and shows the post again, Remove deletes it.
  class FeedController < BaseController
    def index
      @posts = Post.where("reports_count > 0 OR hidden").order(reports_count: :desc, created_at: :desc)
        .preload(:event, :user).page(params[:page]).per(50)
    end

    def keep
      post = Post.find(params.expect(:id))
      Post.transaction do
        post.post_reports.delete_all
        post.update_columns(hidden: false, reports_count: 0) # rubocop:disable Rails/SkipsModelValidations -- counter column
      end
      Audit.record("post_kept", subject: post.user, event: post.event, post_id: post.id)
      redirect_to admin_feed_path, notice: t("admin.feed.kept")
    end

    def remove
      post = Post.find(params.expect(:id))
      post.destroy!
      Audit.record("post_removed", subject: post.user, event: post.event, post_id: post.id, by: current_user.id)
      redirect_to admin_feed_path, notice: t("admin.feed.removed")
    end
  end
end
