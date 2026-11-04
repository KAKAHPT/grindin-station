# frozen_string_literal: true

class AddFormatToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :format, :string, default: "multiplayer", null: false
    add_column :events, :match_games, :integer, default: 3, null: false
  end
end
