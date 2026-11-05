# frozen_string_literal: true

# Errors reported to Rails.error (M9 admin), grouped by fingerprint on /admin/errors. Trimmed after 90 days.
class CreateErrorEvents < ActiveRecord::Migration[8.1]
  def change # rubocop:disable Metrics/MethodLength -- one line per column
    create_table :error_events, id: :uuid do |t|
      t.string :fingerprint, null: false, index: true
      t.string :error_class
      t.text :message
      t.text :backtrace
      t.string :path
      t.string :request_id
      t.uuid :user_id
      t.string :source
      t.datetime :resolved_at
      t.datetime :created_at, null: false, index: true
    end
  end
end
