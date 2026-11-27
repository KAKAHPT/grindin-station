# frozen_string_literal: true

# The organizer can keep an event's date unannounced: the public pages say "Date to be announced" and the stored
# date only orders the lists.
class AddDateTbaToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :date_tba, :boolean, default: false, null: false
  end
end
