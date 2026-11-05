# frozen_string_literal: true

# M15 D1: the Magic game format of an event; multiplayer is always commander, existing 1v1 events become "other".
class AddGameFormatToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :game_format, :string, null: false, default: "commander"
    execute "UPDATE events SET game_format = 'other' WHERE format = 'one_v_one'"
  end

  def down
    remove_column :events, :game_format
  end
end
