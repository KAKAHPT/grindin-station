# frozen_string_literal: true

# One reader's report of a post; the third one hides the post until an admin reviews it.
class PostReport < ApplicationRecord
  belongs_to :post, counter_cache: :reports_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :post_id }

  after_create_commit { post.hide_if_reported! }
end
