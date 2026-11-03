# frozen_string_literal: true

class AddShowDecklistsToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :show_decklists, :boolean, default: false, null: false
  end
end
