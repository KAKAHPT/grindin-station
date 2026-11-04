# frozen_string_literal: true

# Day roster: waitlist, why and when a player dropped, when they checked in.
class AddWaitlistAndDropInfoToEventParticipants < ActiveRecord::Migration[8.1]
  def change
    change_table :event_participants, bulk: true do |t|
      t.boolean :waitlisted, default: false, null: false
      t.integer :waitlist_position
      t.datetime :dropped_at
      t.string :drop_reason
      t.datetime :checked_in_at
    end
  end
end
