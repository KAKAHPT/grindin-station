# frozen_string_literal: true

require "test_helper"

class PlayerTest < ActiveSupport::TestCase
  setup { @player = players(:player_one) }

  test "reporting_email falls back to the sign-in e-mail" do
    assert_equal "player1@example.com", @player.reporting_email
  end

  test "reporting_email prefers the Wizards e-mail" do
    @player.update!(wizards_email: "wiz@example.com")

    assert_equal "wiz@example.com", @player.reporting_email
  end

  test "wizards_email is stripped and downcased" do
    @player.update!(wizards_email: "  Wiz@Example.COM ")

    assert_equal "wiz@example.com", @player.reload.wizards_email
  end

  test "a blank wizards_email is stored as nil and falls back" do
    @player.update!(wizards_email: "   ")

    assert_nil @player.reload.wizards_email
    assert_equal "player1@example.com", @player.reporting_email
  end

  test "an invalid wizards_email is rejected" do
    @player.wizards_email = "not-an-email"

    assert_not @player.valid?
    assert @player.errors.of_kind?(:wizards_email, :invalid)
  end

  test "a player without a user and without a Wizards e-mail has no reporting e-mail" do
    assert_nil Player.new(key: "x").reporting_email
  end
end
