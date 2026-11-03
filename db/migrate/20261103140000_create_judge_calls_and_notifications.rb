# frozen_string_literal: true

# Players call a judge to a table; staff and players get generic in-app notifications.
class CreateJudgeCallsAndNotifications < ActiveRecord::Migration[8.1]
  def change
    create_judge_calls
    create_notifications
  end

  private

  def create_judge_calls # rubocop:disable Metrics/MethodLength -- one line per column
    create_table :judge_calls, id: :uuid do |t|
      t.references :event, type: :uuid, null: false, foreign_key: true, index: false
      t.references :pod, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :event_participant, type: :uuid, foreign_key: { on_delete: :nullify }, index: false
      t.text :reason
      t.string :status, null: false, default: "open"
      t.references :acknowledged_by_user, type: :uuid, index: false,
                                          foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :acknowledged_at
      t.datetime :closed_at
      t.timestamps
    end
    add_index :judge_calls, %i[event_id status]
  end

  def create_notifications
    create_table :notifications, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.references :subject, type: :uuid, polymorphic: true
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, %i[user_id read_at]
  end
end
