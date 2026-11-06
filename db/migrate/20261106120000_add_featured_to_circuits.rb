# frozen_string_literal: true

# Admins feature a circuit (an ECL season, a championship): first on /circuits and on the landing.
class AddFeaturedToCircuits < ActiveRecord::Migration[8.1]
  def change
    add_column :circuits, :featured, :boolean, null: false, default: false
    add_index :circuits, :featured, where: "featured"
  end
end
