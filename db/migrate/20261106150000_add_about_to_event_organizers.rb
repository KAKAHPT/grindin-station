# frozen_string_literal: true

# The organizer's About: a description, where they are and their links (website, Instagram, Discord, YouTube, Twitch, X),
# edited in organizer mode and shown on /o/:handle.
class AddAboutToEventOrganizers < ActiveRecord::Migration[8.1]
  def change
    add_column :event_organizers, :description, :text
    add_column :event_organizers, :location, :string
    add_column :event_organizers, :links, :jsonb, null: false, default: {}
  end
end
