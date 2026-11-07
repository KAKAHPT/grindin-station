# frozen_string_literal: true

# E-mail confirmation for the public sign-up: a new account stays unconfirmed (no password sign-in) until its
# confirmation link is opened. Everything else that creates users (OAuth with a provider-verified e-mail, an
# organizer adding a player, tests, seeds) and every existing account is confirmed by the column default.
class AddConfirmedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :confirmed_at, :datetime, default: -> { "CURRENT_TIMESTAMP" }
  end
end
