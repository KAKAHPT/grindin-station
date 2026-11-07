# frozen_string_literal: true

# Teams as records: a name, an owner and memberships (requested by the player, invited by the owner, accepted).
# users.team keeps the accepted team's name, as the rankings read it. Existing team names become teams owned by
# their oldest member, everyone who had the name as an accepted member.
class CreateTeams < ActiveRecord::Migration[8.1]
  def up
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

    say_with_time("teams from users.team") { backfill }
  end

  def down
    drop_table :team_memberships
    drop_table :teams
  end

  private

  def backfill
    execute <<~SQL.squish
        INSERT INTO teams (name, owner_id, created_at, updated_at)
        SELECT DISTINCT ON (lower(team)) team, id, now(), now()
        FROM users WHERE team IS NOT NULL AND anonymized_at IS NULL
        ORDER BY lower(team), created_at
    SQL
    execute <<~SQL.squish
        INSERT INTO team_memberships (team_id, user_id, status, created_at, updated_at)
        SELECT teams.id, users.id, 'accepted', now(), now()
        FROM users JOIN teams ON lower(teams.name) = lower(users.team)
        WHERE users.anonymized_at IS NULL
    SQL
  end
end
