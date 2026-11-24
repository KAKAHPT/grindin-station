# frozen_string_literal: true

# An event can be by invitation: only the accounts the organizer invited may register themselves.
class AddInvitationOnlyEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :invitation_only, :boolean, default: false, null: false

    create_table :event_invitations, id: :uuid do |t|
      t.references :event, type: :uuid, null: false, foreign_key: true, index: false
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :invited_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index %i[event_id user_id], unique: true
    end
  end
end
