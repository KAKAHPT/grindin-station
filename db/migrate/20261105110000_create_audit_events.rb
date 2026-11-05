# frozen_string_literal: true

# Who did what, when and from where, for sensitive actions (M9 admin). Rows outlive their actor and event.
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events, id: :uuid do |t|
      t.string :action, null: false, index: true
      t.references :actor_user, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :subject, type: :uuid, polymorphic: true, index: false
      t.references :event, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :ip
      t.string :request_id
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false, index: true
    end
  end
end
