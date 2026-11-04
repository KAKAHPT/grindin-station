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

  test "an eight-character password signs up" do
    assert_difference("User.count", 1) { sign_up("eightch8") }
    assert_redirected_to root_path
  end

  test "an admin param on sign-up is ignored" do
    post registrations_path, params: { user: { name: "Sneaky", email_address: "sneaky@example.com", admin: "true",
                                               password: "eightch8", password_confirmation: "eightch8" } }

    assert_not User.find_by!(email_address: "sneaky@example.com").admin?
  end
end
