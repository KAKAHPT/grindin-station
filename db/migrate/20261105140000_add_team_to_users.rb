# frozen_string_literal: true

class AddTeamToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :team, :string
  end
end
