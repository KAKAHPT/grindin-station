# frozen_string_literal: true

# M13 rankings: one contribution row per (player, finished event) and one Elo row per (player, season; nil = all
# time), both rebuilt by Rankings::Rebuild. Plus the event's country (filters) and admin tier (invitational points).
class CreateRankingTables < ActiveRecord::Migration[8.1]
  def change # rubocop:disable Metrics/MethodLength,Metrics/AbcSize -- one line per column
    create_table :ranking_contributions, id: :uuid do |t|
      t.uuid :player_id, null: false
      t.uuid :event_id, null: false
      t.integer :season, null: false, index: true
      t.string :country, limit: 2, index: true
      t.string :team, index: true
      t.uuid :event_organizer_id, index: true
      t.string :format, null: false
      t.integer :field, null: false
      t.integer :wins, null: false, default: 0
      t.integer :draws, null: false, default: 0
      t.integer :losses, null: false, default: 0
      t.integer :byes, null: false, default: 0
      t.boolean :made_cut, null: false, default: false
      t.boolean :top4, null: false, default: false
      t.boolean :won, null: false, default: false
      t.decimal :points, precision: 8, scale: 2, null: false, default: 0
      t.decimal :invitational_points, precision: 8, scale: 2, null: false, default: 0
      t.timestamps
      t.index %i[player_id event_id], unique: true
      t.index :event_id
    end

    create_table :elo_ratings, id: :uuid do |t|
      t.uuid :player_id, null: false
      t.integer :season
      t.decimal :rating, precision: 8, scale: 2, null: false, default: 1500
      t.decimal :previous_rating, precision: 8, scale: 2, null: false, default: 1500
      t.decimal :peak, precision: 8, scale: 2, null: false, default: 1500
      t.integer :games, null: false, default: 0
      t.integer :wins, null: false, default: 0
      t.timestamps
      t.index %i[player_id season], unique: true, nulls_not_distinct: true
    end

    add_column :events, :country, :string, limit: 2
    add_column :events, :tier, :string, null: false, default: "none"
  end
end
