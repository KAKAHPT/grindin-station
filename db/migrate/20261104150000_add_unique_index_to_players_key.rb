# frozen_string_literal: true

class AddUniqueIndexToPlayersKey < ActiveRecord::Migration[8.1]
  def change
    remove_index :players, :key
    add_index :players, :key, unique: true
  end
end
