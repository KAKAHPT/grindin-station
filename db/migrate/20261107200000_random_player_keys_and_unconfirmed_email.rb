# frozen_string_literal: true

# players.key becomes an opaque random id (it was MD5(e-mail + name), reversible offline); existing keys are
# rotated, guests and removed players keep theirs. users.unconfirmed_email holds an e-mail change until the
# link sent to the new address is opened.
class RandomPlayerKeysAndUnconfirmedEmail < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :unconfirmed_email, :string
    execute <<~SQL.squish
      UPDATE players SET key = 'p-' || encode(gen_random_bytes(12), 'hex')
      WHERE key !~ '^(guest|removed|p)-'
    SQL
  end

  def down
    remove_column :users, :unconfirmed_email
  end
end
