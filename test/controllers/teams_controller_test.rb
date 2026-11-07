# frozen_string_literal: true

require "test_helper"

# Teams on the account page: create, ask to join, invite, accept, leave; users.team follows the accepted team.
class TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:player_one)
    @joiner = users(:player_two)
    sign_in(@owner)
  end

  test "creating a team makes its creator the owner and an accepted member, and writes users.team" do
    post teams_path, params: { team: { name: "  Porto  Grinders " } }

    assert_redirected_to account_path(anchor: "team")
    team = Team.find_by!(name: "Porto Grinders")
    assert_equal @owner, team.owner
    assert_equal "Porto Grinders", @owner.reload.team
    get account_path
    assert_select "[data-team-card] [data-team-name]", text: "Porto Grinders"
    assert_select "[data-team-card] [data-team-invite]"

    post teams_path, params: { team: { name: "porto grinders" } }
    assert_equal 1, Team.count
    post teams_path, params: { team: { name: "Another" } }
    assert_equal 1, Team.count, "one accepted team per player"
  end

  test "a player asks to join, the owner accepts; the team's name lands on the player's account" do
    team = create_team("Lisboa Stax")
    sign_in(@joiner)
    get account_path
    assert_select "[data-team-card] [data-team-join] option", text: "Lisboa Stax"
    post team_memberships_path, params: { team_id: team.id }
    membership = team.memberships.find_by!(user: @joiner)
    assert_equal "requested", membership.status
    assert_nil @joiner.reload.team
    assert_equal 1, @owner.notifications.where(kind: "team_requested").count

    patch team_membership_path(membership)
    assert_equal "requested", membership.reload.status, "only the owner accepts a request"

    sign_in(@owner)
    get account_path
    assert_select "[data-team-pending] [data-team-request-row]", text: /#{@joiner.name}/
    patch team_membership_path(membership)
    assert_equal "accepted", membership.reload.status
    assert_equal "Lisboa Stax", @joiner.reload.team
    assert_equal 1, @joiner.notifications.where(kind: "team_accepted").count
  end

  test "the owner invites by handle, the player accepts or declines" do
    team = create_team("Braga Bombers")
    post team_memberships_path, params: { team_id: team.id, handle: "@#{@joiner.handle}" }
    membership = team.memberships.find_by!(user: @joiner)
    assert_equal "invited", membership.status
    assert_equal 1, @joiner.notifications.where(kind: "team_invited").count

    sign_in(@joiner)
    get account_path
    assert_select "[data-team-pending] [data-team-invitation]", text: /Braga Bombers/
    delete team_membership_path(membership)
    assert_not TeamMembership.exists?(membership.id)

    sign_in(@owner)
    post team_memberships_path, params: { team_id: team.id, handle: @joiner.handle }
    sign_in(@joiner)
    patch team_membership_path(team.memberships.find_by!(user: @joiner))
    assert_equal "Braga Bombers", @joiner.reload.team
  end

  test "a team takes at most five players; only its owner invites" do
    team = create_team("Full House")
    4.times do |i|
      user = User.create!(name: "P#{i}", email_address: "p#{i}-#{SecureRandom.hex(3)}@example.com",
                          password: "password123")
      team.memberships.create!(user: user, status: "accepted")
    end
    assert team.reload.full?

    post team_memberships_path, params: { team_id: team.id, handle: @joiner.handle }
    assert_equal "invited", team.memberships.find_by!(user: @joiner).status
    sign_in(@joiner)
    patch team_membership_path(team.memberships.find_by!(user: @joiner))
    assert_equal "invited", team.memberships.find_by!(user: @joiner).status, "no room"
    assert_nil @joiner.reload.team

    post team_memberships_path, params: { team_id: team.id, handle: users(:player_three).handle }
    assert_not team.memberships.exists?(user: users(:player_three))
  end

  test "leaving clears users.team; the owner leaving hands the team to the oldest member" do
    team = create_team("Coimbra Combo")
    joiner = team.memberships.create!(user: @joiner, status: "accepted")
    assert_equal "Coimbra Combo", @joiner.reload.team

    delete team_membership_path(team.memberships.find_by!(user: @owner))
    assert_nil @owner.reload.team
    assert_equal @joiner, team.reload.owner

    sign_in(@joiner)
    delete team_membership_path(joiner)
    assert_nil @joiner.reload.team
    assert_not Team.exists?(team.id)
  end

  private

  def create_team(name)
    Team.create!(name: name, owner: @owner).tap { |team| team.memberships.create!(user: @owner, status: "accepted") }
  end

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
