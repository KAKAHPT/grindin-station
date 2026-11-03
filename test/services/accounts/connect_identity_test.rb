# frozen_string_literal: true

require "test_helper"

module Accounts
  class ConnectIdentityTest < ActiveSupport::TestCase
    def auth(uid: "g-1", email: "player1@example.com", name: "Player One")
      OmniAuth::AuthHash.new(provider: "google_oauth2", uid: uid, info: { email: email, name: name })
    end

    test "identidade conhecida devolve o seu user" do
      user = users(:player_two)
      user.identities.create!(provider: "google_oauth2", uid: "g-1")

      assert_no_difference -> { Identity.count } do
        assert_equal user, ConnectIdentity.call(auth: auth)
      end
    end

    test "e-mail igual liga à conta existente sem criar user" do
      assert_no_difference -> { User.count } do
        assert_difference -> { Identity.count }, 1 do
          user = ConnectIdentity.call(auth: auth(email: "  Player1@Example.com "))

          assert_equal users(:player_one), user
          assert_equal %w[google_oauth2 g-1], [user.identities.last.provider, user.identities.last.uid]
        end
      end
    end

    test "e-mail novo cria user e player" do
      assert_difference -> { User.count } => 1, -> { Player.count } => 1, -> { Identity.count } => 1 do
        user = ConnectIdentity.call(auth: auth(email: "new@example.com", name: "New Person"))

        assert_equal "new@example.com", user.email_address
        assert_equal "New Person", user.name
        assert user.player.present?
        assert_equal "new@example.com", user.identities.sole.email
      end
    end

    test "com current_user liga a esse user mesmo com e-mail diferente" do
      current = users(:player_three)

      assert_no_difference -> { User.count } do
        user = ConnectIdentity.call(auth: auth(email: "someone-else@example.com"), current_user: current)

        assert_equal current, user
        assert_equal current, Identity.find_by(provider: "google_oauth2", uid: "g-1").user
      end
    end
  end
end
