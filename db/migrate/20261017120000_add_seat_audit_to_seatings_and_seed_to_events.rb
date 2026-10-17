# frozen_string_literal: true

# Seat audit: how each seat was assigned ("fair" in swiss, "ranked" in the top cut) and the fair order's cost;
# events.seed makes the fair-seating tie-breaks reproducible.
class AddSeatAuditToSeatingsAndSeedToEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :seatings, bulk: true do |t|
      t.string :assigned_by, null: false, default: "fair"
      t.integer :cost
    end
    add_column :events, :seed, :integer
  end
end
