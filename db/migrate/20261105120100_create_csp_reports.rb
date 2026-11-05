# frozen_string_literal: true

# Content security policy violations posted by browsers (M9 admin). Trimmed after 30 days.
class CreateCspReports < ActiveRecord::Migration[8.1]
  def change
    create_table :csp_reports, id: :uuid do |t|
      t.string :document_uri
      t.string :violated_directive
      t.string :blocked_uri
      t.string :user_agent
      t.string :ip
      t.datetime :created_at, null: false, index: true
    end
  end
end
