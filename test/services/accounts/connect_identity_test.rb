# frozen_string_literal: true

require "test_helper"

module Accounts
  class ConnectIdentityTest < ActiveSupport::TestCase
    def auth(uid: "g-1", email: "player1@example.com", name: "Player One", verified: true)
      OmniAuth::AuthHash.new(provider: "google_oauth2", uid: uid, info: { email: email, name: name },
                             extra: { raw_info: { email: email, email_verified: verified } })
    end

    def discord_auth(verified:)
      OmniAuth::AuthHash.new(provider: "discord", uid: "d-1", info: { email: "player1@example.com", name: "p1" },
                             extra: { raw_info: { email: "player1@example.com", verified: verified } })
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

    test "user criado por OAuth fica sem palavra-passe definida" do
      assert_not ConnectIdentity.call(auth: auth(email: "new@example.com", name: "New Person")).password_set
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

    test "e-mail não verificado de conta existente recusa sem criar identidade" do
      assert_no_difference [-> { User.count }, -> { Identity.count }] do
        assert_raises(ConnectIdentity::UnverifiedEmail) { ConnectIdentity.call(auth: auth(verified: false)) }
        assert_raises(ConnectIdentity::UnverifiedEmail) { ConnectIdentity.call(auth: discord_auth(verified: false)) }
      end
    end

    test "discord verificado liga à conta existente" do
      assert_equal users(:player_one), ConnectIdentity.call(auth: discord_auth(verified: true))
    end

    test "e-mail não verificado sem conta existente cria user novo" do
      assert_difference -> { User.count } => 1, -> { Identity.count } => 1 do
        user = ConnectIdentity.call(auth: auth(email: "fresh@example.com", verified: false))

        assert_equal "fresh@example.com", user.email_address
      end
    end

    test "e-mail não verificado com current_user liga a esse user" do
      current = users(:player_three)

      assert_equal current, ConnectIdentity.call(auth: auth(verified: false), current_user: current)
    end
  end
end
