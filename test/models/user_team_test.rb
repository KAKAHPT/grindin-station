# frozen_string_literal: true

require "test_helper"

class UserTeamTest < ActiveSupport::TestCase
  setup { @user = users(:player_one) }

  test "team up to 30 characters is valid, 31 is not" do
    @user.team = "a" * 30

    assert_predicate @user, :valid?

    @user.team = "a" * 31

    assert_not @user.valid?
    assert @user.errors.of_kind?(:team, :too_long)
  end

  test "team is stripped and blank becomes nil" do
    @user.team = "  Porto Grinders "

    assert_equal "Porto Grinders", @user.team

    @user.team = "   "

    assert_nil @user.team
  end

  test "team_suggestions lists the distinct teams in order" do
    users(:player_one).update!(team: "Zeta")
    users(:player_two).update!(team: "Alpha")

    assert_equal %w[Alpha Zeta], User.team_suggestions
  end
end
