# frozen_string_literal: true

# Each participant's rank when a round closed, for the movement arrows of the standings.
class CreateStandingsSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :standings_snapshots, id: :uuid do |t|
      t.references :event, type: :uuid, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :round_number, null: false
      t.references :event_participant, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.integer :rank, null: false
      t.timestamps
    end
    add_index :standings_snapshots, %i[event_id round_number event_participant_id],
              unique: true, name: "index_standings_snapshots_unique"
  end
end
