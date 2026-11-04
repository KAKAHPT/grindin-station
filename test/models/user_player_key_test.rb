# frozen_string_literal: true

require "test_helper"

class UserPlayerKeyTest < ActiveSupport::TestCase
  def sign_up(email, name)
    User.create(name: name, email_address: email, password: "password123")
  end

  test "e-mail and name that concatenate alike get different players" do
    first = sign_up("a@x.com", "bc")
    second = sign_up("a@x.comb", "c")

    assert second.persisted?
    assert_not_equal first.player.id, second.player.id
    assert_equal first.id, first.player.reload.user_id
    assert_equal second.id, second.player.user_id
  end

  test "the Ana Silva pair gets different players and the first is untouched" do
    first = sign_up("ana@gmail.com", "Ana Silva")
    key = first.player.key
    second = sign_up("ana@gmail.comAna", " Silva")

    assert_not_equal first.player.id, second.player&.id
    assert_equal first.id, first.player.reload.user_id
    assert_equal key, first.player.key
  end

  test "a player owned by another user is never adopted" do
    owner = sign_up("owner@example.com", "Owner")
    intruder = User.new(name: "Intruder", email_address: "intruder@example.com", password: "password123")
    owner.player.update!(key: intruder.compute_key)

    intruder.save!

    assert_not_equal owner.player.id, intruder.player.id
    assert_equal owner.id, owner.player.reload.user_id
    assert intruder.player.key.start_with?("#{intruder.compute_key}-")
  end

  test "an unowned player with the key is adopted" do
    user = User.new(name: "Late", email_address: "late@example.com", password: "password123")
    unowned = Player.create!(key: user.compute_key)

    user.save!

    assert_equal unowned.id, user.player.id
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
