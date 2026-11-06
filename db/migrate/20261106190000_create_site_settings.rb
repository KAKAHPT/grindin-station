# frozen_string_literal: true

# Site-wide switches the admins flip (first one: the social feed's pause), as key/value rows.
class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :key, null: false
      t.string :value
      t.timestamps
    end
    add_index :site_settings, :key, unique: true
  end
end
