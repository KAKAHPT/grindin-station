# frozen_string_literal: true

class AddUnevenFieldToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :uneven_field, :string, null: false, default: "pods_of_three"
  end
end
