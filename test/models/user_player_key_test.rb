# frozen_string_literal: true

require "test_helper"

# Every account gets its own player with an opaque random key.
class UserPlayerKeyTest < ActiveSupport::TestCase
  def sign_up(email, name)
    User.create(name: name, email_address: email, password: "password123")
  end

  test "two accounts get different players, each owned by its user" do
    first = sign_up("a@x.com", "bc")
    second = sign_up("a@x.comb", "c")

    assert second.persisted?
    assert_not_equal first.player.id, second.player.id
    assert_equal first.id, first.player.reload.user_id
    assert_equal second.id, second.player.user_id
  end

  test "the key is random, never derived from the e-mail and name, and survives a rename" do
    user = sign_up("ana@gmail.com", "Ana Silva")
    key = user.player.key

    assert_match(/\Ap-\h{24}\z/, key)
    assert_not_equal Digest::MD5.hexdigest("ana@gmail.com\0Ana Silva"), key
    user.update!(name: "Ana S.", email_address: "ana2@gmail.com")
    assert_equal key, user.player.reload.key
  end

  test "initializing the player again keeps the one the user has" do
    user = sign_up("again@example.com", "Again")
    player = user.player

    assert_no_difference -> { Player.count } do
      user.initialize_player
    end
    assert_equal player.id, user.reload.player.id
  end

  test "a malformed e-mail is refused" do
    user = sign_up("not an e-mail", "Someone")

    assert user.errors.added?(:email_address, :invalid, value: "not an e-mail")
  end

  test "player keys are unique in the database" do
    Player.create!(key: "same-key")

    assert_raises(ActiveRecord::RecordNotUnique) { Player.create!(key: "same-key") }
  end

  test "a participant added by e-mail never takes another user's player" do
    first = sign_up("a@x.com", "bc")
    participant = EventParticipant.create!(event: events(:small_tournament), player_email: "a@x.comb",
                                           player_name: "c", accepted_terms: true)

    assert_not_equal first.player.id, participant.player_id
    assert_equal "a@x.comb", participant.player.user.email_address
    assert_equal first.id, first.player.reload.user_id
  end
end
