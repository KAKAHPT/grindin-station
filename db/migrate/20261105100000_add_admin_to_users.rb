# frozen_string_literal: true

# Site administrators: set only from the console / `rails grindin:admin[email]`, never from a form.
class AddAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, null: false, default: false
  end
end
