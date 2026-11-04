# frozen_string_literal: true

class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  # Bare model so the backfill does not depend on the app's User callbacks.
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    change_table :users, bulk: true do |t|
      t.string :handle
      t.string :country, limit: 2
      t.text :bio
      t.string :visibility, null: false, default: "public"
      t.datetime :anonymized_at
      t.boolean :password_set, null: false, default: true
    end

    backfill_handles
    add_index :users, :handle, unique: true
  end

  def down
    remove_index :users, :handle
    change_table :users, bulk: true do |t|
      t.remove :handle, :country, :bio, :visibility, :anonymized_at, :password_set
    end
  end

  private

  def backfill_handles
    MigrationUser.reset_column_information
    taken = Set.new
    MigrationUser.order(:created_at).find_each do |user|
      handle = next_handle(user.name, taken)
      taken << handle
      user.update_columns(handle: handle) # rubocop:disable Rails/SkipsModelValidations -- one-off backfill
    end
  end

  # Same rule as User#assign_handle: parameterized name, then "-2", "-3"... on collision.
  def next_handle(name, taken)
    base = name.to_s.parameterize.tr("_", "-").first(26).delete_suffix("-")
    base = "player" if base.length < 3
    handle = base
    suffix = 1
    handle = "#{base}-#{suffix += 1}" while taken.include?(handle)
    handle
  end
end
