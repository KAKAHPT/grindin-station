# frozen_string_literal: true

# M16: registration and check-in options. Decklists are optional unless the organizer requires them; players
# check themselves in from the event page once the window before the start opens.
class AddRegistrationSettingsToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :decklist_required, :boolean, null: false, default: false
    add_column :events, :self_check_in_enabled, :boolean, null: false, default: true
    add_column :events, :check_in_opens_hours_before, :integer, null: false, default: 3
  end
end
