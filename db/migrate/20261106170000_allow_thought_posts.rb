# frozen_string_literal: true

# Posts without an event ("thoughts"): the event becomes optional.
class AllowThoughtPosts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :posts, :event_id, true
  end
end
