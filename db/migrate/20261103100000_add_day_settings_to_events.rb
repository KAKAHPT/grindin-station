# frozen_string_literal: true

# Day-of-event settings. None of these are locked by tournament state.
class AddDaySettingsToEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :events, bulk: true do |t|
      t.boolean :self_report_enabled, null: false, default: true
      t.string :result_confirmation, null: false, default: "none"
      t.integer :confirmation_timeout_minutes, null: false, default: 5
      t.boolean :waitlist_enabled, null: false, default: false
      t.boolean :show_commanders_in_standings, null: false, default: false
      t.string :top_cut_timeout_rule, null: false, default: "highest_seed_advances"
    end
  end
end
