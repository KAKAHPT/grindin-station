# frozen_string_literal: true

# Leagues where the players open their own tables: the league's scoring settings, the waiting tables
# (league_tables + league_table_seats) and a per-pod clock.
class AddLeagueOpenTables < ActiveRecord::Migration[8.1]
  def change # rubocop:disable Metrics/AbcSize,Metrics/MethodLength -- one schema change
    add_column :events, :starting_points, :integer, default: 1000, null: false
    add_column :events, :draw_rule, :string, default: "split", null: false
    add_column :events, :min_games_for_cut, :integer, default: 10, null: false
    add_column :events, :max_games_per_week, :integer
    add_column :events, :max_games_vs_same_opponent, :integer

    add_column :pods, :clock_started_at, :datetime

    create_table :league_tables, id: :uuid do |t|
      t.references :event, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :opener, type: :uuid, null: false,
                            foreign_key: { to_table: :event_participants, on_delete: :cascade }
      t.string :state, default: "waiting", null: false
      t.references :pod, type: :uuid, foreign_key: { on_delete: :nullify }
      t.datetime :filled_at
      t.datetime :stale_notified_at
      t.text :cancel_reason
      t.references :cancel_requested_by, type: :uuid,
                                         foreign_key: { to_table: :event_participants, on_delete: :nullify }
      t.datetime :cancel_requested_at
      t.string :cancel_state
      t.references :cancel_decided_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :cancel_decided_at
      t.timestamps
      t.index %i[event_id state]
    end

    create_table :league_table_seats, id: :uuid do |t|
      t.references :league_table, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :event_participant, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.boolean :active, default: true, null: false
      t.timestamps
      t.index %i[league_table_id event_participant_id], unique: true
      t.index :event_participant_id, unique: true, where: "active", name: "index_league_table_seats_one_active"
    end
  end
end
