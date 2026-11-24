# frozen_string_literal: true

# An admin suspends an organizer who misbehaves: no organizer access, unfinished events off the public site.
class AddSuspendedAtToEventOrganizers < ActiveRecord::Migration[8.1]
  def change
    add_column :event_organizers, :suspended_at, :datetime
  end
end
