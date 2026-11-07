# frozen_string_literal: true

require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def sign_up(password)
    post registrations_path, params: { user: { name: "New Player", email_address: "new-player@example.com",
                                               password: password, password_confirmation: password } }
  end

  test "a blank or short password is refused on sign-up" do
    ["", "short"].each do |password|
      assert_no_difference("User.count") { sign_up(password) }
      assert_response :unprocessable_entity
    end
  end

  test "an eight-character password signs up: no session yet, a confirmation mail" do
    assert_emails 1 do
      assert_difference("User.count", 1) { sign_up("eightch8") }
    end
    assert_redirected_to new_session_path
    user = User.find_by!(email_address: "new-player@example.com")
    assert_not user.confirmed?
    assert_empty user.sessions
  end

  test "the organizer flag on sign-up is ignored: organizing is granted by an admin, and every account gets a player" do
    post registrations_path, params: { user: { name: "Keen", email_address: "keen@example.com", organizer: "1",
                                               password: "eightch8", password_confirmation: "eightch8" } }

    user = User.find_by!(email_address: "keen@example.com")
    assert_nil user.event_organizer
    assert user.player.present?
    assert_select "input[name='user[organizer]']", count: 0 if response.body.include?("<form")
  end

  test "an admin param on sign-up is ignored" do
    post registrations_path, params: { user: { name: "Sneaky", email_address: "sneaky@example.com", admin: "true",
                                               password: "eightch8", password_confirmation: "eightch8" } }

    assert_not User.find_by!(email_address: "sneaky@example.com").admin?
  end
end
