# frozen_string_literal: true

# One entry per player and event. Exact duplicates are removed first, keeping the oldest row.
class AddUniquePlayerPerEvent < ActiveRecord::Migration[8.1]
  def up # rubocop:disable Metrics/MethodLength
    add_column :players, :guest_name, :string # name of a player added by hand, without an account
    execute <<~SQL.squish
      DELETE FROM event_participants ep
      USING event_participants keep
      WHERE ep.player_id IS NOT NULL
        AND ep.event_id = keep.event_id
        AND ep.player_id = keep.player_id
        AND (keep.created_at, keep.id) < (ep.created_at, ep.id)
    SQL
    add_index :event_participants, %i[event_id player_id], unique: true, where: "player_id IS NOT NULL",
                                                           name: "index_event_participants_on_event_id_and_player_id"
  end

  def down
    remove_column :players, :guest_name
    remove_index :event_participants, name: "index_event_participants_on_event_id_and_player_id"
  end
end
