# frozen_string_literal: true

# The feed: short posts about a finished event by its players or organizer (and one made by the app with the
# winner), with one like per person.
class CreatePosts < ActiveRecord::Migration[8.1]
  def change # rubocop:disable Metrics/MethodLength -- two tables
    create_table :posts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :event, type: :uuid, null: false, foreign_key: true
      t.string :kind, null: false, default: "report"
      t.text :body, null: false
      t.integer :likes_count, null: false, default: 0
      t.timestamps
    end
    add_index :posts, :created_at

    create_table :post_likes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :post, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :post_likes, %i[post_id user_id], unique: true
  end
end
