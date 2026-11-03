# frozen_string_literal: true

# Player self-reporting: a pending result awaiting confirmations, disputes and the review timeout.
class AddReportingStateToPods < ActiveRecord::Migration[8.1]
  def change
    change_table :pods, bulk: true do |t|
      t.jsonb :pending_result
      t.references :reported_by_participant, type: :uuid, index: false,
                                             foreign_key: { to_table: :event_participants, on_delete: :nullify }
      t.datetime :reported_at
      t.jsonb :confirmations, null: false, default: {}
      t.boolean :disputed, null: false, default: false
      t.datetime :review_requested_at
    end
  end
end
