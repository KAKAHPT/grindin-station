# frozen_string_literal: true

# Teams as records: a name, an owner and memberships (requested by the player, invited by the owner, accepted).
# users.team keeps the accepted team's name, as the rankings read it. The free-text tags that existed before are not
# turned into teams: a tag proves nothing about who founded a team, so each team is created by whoever claims it.
class CreateTeams < ActiveRecord::Migration[8.1]
  def change # rubocop:disable Metrics/MethodLength -- two tables
    create_table :teams, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.references :owner, type: :uuid, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :teams, "lower(name)", unique: true

    create_table :team_memberships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :team, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false, default: "accepted"
      t.timestamps
    end
    add_index :team_memberships, %i[team_id user_id], unique: true
  end
end
