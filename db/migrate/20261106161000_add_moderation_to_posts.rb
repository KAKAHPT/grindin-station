# frozen_string_literal: true

# Feed moderation: readers report a post (one report per person); three reports hide it until an admin keeps or
# removes it on /admin/feed.
class AddModerationToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :hidden, :boolean, null: false, default: false
    add_column :posts, :reports_count, :integer, null: false, default: 0
    add_index :posts, :reports_count, where: "reports_count > 0"

    create_table :post_reports, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :post, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :post_reports, %i[post_id user_id], unique: true
  end
end
