# frozen_string_literal: true

# Organisers asking to join while organising is by invitation (landing waiting-list card).
class CreateWaitlistSignups < ActiveRecord::Migration[8.1]
  def change
    create_table :waitlist_signups, id: :uuid do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.datetime :created_at, null: false
    end
    add_index :waitlist_signups, :email, unique: true
  end
end
