# frozen_string_literal: true

require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  test "provider and uid are unique together" do
    user = users(:player_one)
    Identity.create!(user: user, provider: "google_oauth2", uid: "123")
    duplicate = Identity.new(user: users(:player_two), provider: "google_oauth2", uid: "123")

    assert_not duplicate.valid?
    assert Identity.new(user: user, provider: "discord", uid: "123").valid?
  end

  test "destroying the user destroys its identities" do
    user = users(:player_one)
    user.identities.create!(provider: "discord", uid: "42")

    assert_difference -> { Identity.count }, -1 do
      user.destroy
    end
  end
end
