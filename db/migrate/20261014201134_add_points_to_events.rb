# frozen_string_literal: true

# Per-event points. Defaults mirror Tournament::POINTS_PER_WIN/DRAW/LOSS/BYE (a bye is worth a win).
class AddPointsToEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :events, bulk: true do |t|
      t.integer :points_win, null: false, default: 7
      t.integer :points_draw, null: false, default: 1
      t.integer :points_loss, null: false, default: 0
      t.integer :points_bye, null: false, default: 7
    end
  end
end
