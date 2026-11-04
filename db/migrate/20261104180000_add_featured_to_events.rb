# frozen_string_literal: true

# Tournaments the organiser puts in the Featured strip of the landing.
class AddFeaturedToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :featured, :boolean, default: false, null: false
    add_index :events, :featured
  end
end
