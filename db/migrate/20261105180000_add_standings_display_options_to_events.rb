# frozen_string_literal: true

# M14: what the public standings show (Beaten, Unique columns; hidden until the tournament ends).
class AddStandingsDisplayOptionsToEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :events, bulk: true do |t|
      t.boolean :show_beaten_in_standings, null: false, default: false
      t.boolean :show_unique_in_standings, null: false, default: false
      t.boolean :hide_standings_until_finished, null: false, default: false
    end
  end
end
