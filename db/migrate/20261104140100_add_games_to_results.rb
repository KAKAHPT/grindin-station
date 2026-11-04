# frozen_string_literal: true

class AddGamesToResults < ActiveRecord::Migration[8.1]
  def change
    add_column :results, :games_won, :integer, default: 0, null: false
    add_column :results, :games_lost, :integer, default: 0, null: false
    add_column :results, :games_drawn, :integer, default: 0, null: false
  end
end
