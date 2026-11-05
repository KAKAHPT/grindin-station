# frozen_string_literal: true

# M15 D6: one Elo rating per player, season and play pool (multiplayer or a 1v1 game format). The old rows mixed
# every 1v1 format, so they are wiped; the next rankings rebuild (bin/rails rankings:rebuild) refills them.
class AddPlayToEloRatings < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM elo_ratings"
    add_column :elo_ratings, :play, :string, null: false, default: "multiplayer"
    remove_index :elo_ratings, %i[player_id season]
    add_index :elo_ratings, %i[player_id season play], unique: true, nulls_not_distinct: true
  end

  def down
    execute "DELETE FROM elo_ratings"
    remove_index :elo_ratings, %i[player_id season play]
    remove_column :elo_ratings, :play
    add_index :elo_ratings, %i[player_id season], unique: true, nulls_not_distinct: true
  end
end
