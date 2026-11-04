# frozen_string_literal: true

# External sign-in accounts (Google, Discord) linked to a user.
class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.string :name
      t.timestamps
    end
    add_index :identities, %i[provider uid], unique: true
  end
end
