# frozen_string_literal: true

# An admin can block an account (/admin/accounts): it cannot sign in until it is unblocked.
class AddBlockedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :blocked_at, :datetime
  end
end
