# frozen_string_literal: true

# Per-event staff: a user working an event as organizer, judge or scorekeeper.
class CreateEventStaff < ActiveRecord::Migration[8.1]
  def change
    create_table :event_staff, id: :uuid do |t|
      t.references :event, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :event_staff, %i[event_id user_id], unique: true
  end
end
