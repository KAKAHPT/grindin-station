# frozen_string_literal: true

class AddWizardsEmailToPlayers < ActiveRecord::Migration[8.0]
  def change
    add_column :players, :wizards_email, :string
  end
end
