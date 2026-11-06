# frozen_string_literal: true

module PostsHelper
  # The post's text with @handles linked to the profiles that exist; everything else escaped.
  def post_body_html(post, mentioned = nil)
    mentioned ||= User.where(handle: post.mentioned_handles).index_by(&:handle)
    safe_join(post.body.to_s.split(/(@[a-z0-9-]{3,30})\b/).map { |piece| mention_link(piece, mentioned) })
  end

  # The feed URL with the current filters, changed by the given keys (nil drops one).
  def feed_url_with(feed, **changes)
    feed_path(**feed.url_params.merge(locale: params[:locale]).merge(changes).compact)
  end

  private

  def mention_link(piece, mentioned)
    user = piece.start_with?("@") && mentioned[piece.delete_prefix("@")]
    return piece unless user

    link_to(piece, profile_path(user.handle, locale: params[:locale]), class: "text-accent hover:underline")
  end
end
