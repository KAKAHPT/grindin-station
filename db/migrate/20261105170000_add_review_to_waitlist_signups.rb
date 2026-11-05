# frozen_string_literal: true

# M13 D17: an admin approves or declines a waiting-list signup.
class AddReviewToWaitlistSignups < ActiveRecord::Migration[8.1]
  def change
    change_table :waitlist_signups, bulk: true do |t|
      t.datetime :approved_at
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :declined_at
    end
  end
end
