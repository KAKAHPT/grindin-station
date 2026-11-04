# frozen_string_literal: true

class AddUniqueIndexToPlayersKey < ActiveRecord::Migration[8.1]
  # Before the unique index: the oldest player keeps a shared key, the others get "<key>-<id>". Nothing is
  # deleted (players carry event history); every renamed row is printed.
  def up
    rename_duplicate_keys
    remove_index :players, :key
    add_index :players, :key, unique: true
  end

  def down
    remove_index :players, :key
    add_index :players, :key
  end

  private

  def rename_duplicate_keys
    duplicates = select_rows(<<~SQL.squish)
      SELECT id, key FROM (
        SELECT id, key, row_number() OVER (PARTITION BY key ORDER BY created_at, id) AS n FROM players
      ) ranked WHERE n > 1
    SQL
    duplicates.each do |id, key|
      say "players.key #{key}: player #{id} renamed to #{key}-#{id}"
      execute "UPDATE players SET key = #{quote("#{key}-#{id}")} WHERE id = #{quote(id)}"
    end
  end
end
