# frozen_string_literal: true

# Following people (players and organizers alike, both are users) and a per-account choice of what the social
# feed shows: everyone, or only the people followed.
class CreateFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :follows, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :follower, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.references :followed, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :follows, %i[follower_id followed_id], unique: true

    add_column :users, :feed_scope, :string, null: false, default: "everyone"
  end
end
