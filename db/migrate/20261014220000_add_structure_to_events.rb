# frozen_string_literal: true

# Per-event structure: swiss rounds and top cut (nil = use Tournaments::Structure.suggested; top cut 0 = no cut),
# and round lengths in minutes.
class AddStructureToEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :events, bulk: true do |t|
      t.integer :swiss_rounds_count
      t.integer :top_cut_size
      t.integer :round_minutes, null: false, default: 80
      t.integer :top_cut_round_minutes, null: false, default: 150
    end
  end
end
