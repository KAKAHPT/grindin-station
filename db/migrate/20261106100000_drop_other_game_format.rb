# frozen_string_literal: true

# "Other 1v1" is no longer offered: any event still on it becomes Standard.
class DropOtherGameFormat < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE events SET game_format = 'standard' WHERE game_format = 'other'"
  end

  def down; end
end
