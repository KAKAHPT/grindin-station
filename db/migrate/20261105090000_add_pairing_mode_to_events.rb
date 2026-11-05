# frozen_string_literal: true

# How multiplayer swiss rounds are paired: swiss (default), random or power.
class AddPairingModeToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :pairing_mode, :string, null: false, default: "swiss"
  end
end
