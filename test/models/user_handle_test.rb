# frozen_string_literal: true

require "test_helper"

class UserHandleTest < ActiveSupport::TestCase
  def create_user(name, email)
    User.create!(name: name, email_address: email, password: "password123")
  end

  test "handle is generated from the name" do
    assert_equal "fabio-batista", create_user("Fábio Batista", "fabio@example.com").handle
  end

  test "colliding handles get a numeric suffix" do
    create_user("Fábio Batista", "fabio1@example.com")

    assert_equal "fabio-batista-2", create_user("Fabio Batista", "fabio2@example.com").handle
    assert_equal "fabio-batista-3", create_user("fabio batista", "fabio3@example.com").handle
  end

  test "short names still produce a valid handle" do
    user = create_user("Al", "al@example.com")

    assert_match User::HANDLE_FORMAT, user.handle
  end

  test "invalid handle edits are rejected" do
    user = create_user("Fábio Batista", "fabio@example.com")
    other = create_user("Other Person", "other@example.com")

    ["ab", "Has Spaces", "UPPER_case", "a" * 31, "", other.handle].each do |handle|
      assert_not user.update(handle: handle), "#{handle.inspect} should be rejected"
    end
    assert user.update(handle: "new-handle-1")
  end

  test "visibility defaults to public and only accepts known values" do
    user = create_user("Fábio Batista", "fabio@example.com")

    assert_equal "public", user.visibility
    assert_equal %w[public participants private], User::VISIBILITIES
    assert_not user.update(visibility: "friends")
  end

  test "avatar must be a small jpeg, png or webp" do
    user = users(:player_one)

    user.avatar.attach(io: StringIO.new("GIF89a"), filename: "a.gif", content_type: "image/gif")
    assert_not user.valid?

    user.avatar.attach(io: file_fixture("cover1.jpg").open, filename: "a.jpg", content_type: "image/jpeg")
    assert user.valid?

    user.avatar.attach(io: StringIO.new("\xFF\xD8\xFF".b + ("0" * 2.megabytes)), filename: "big.jpg",
                       content_type: "image/jpeg")
    assert_not user.valid?
  end

  test "display_name and player name are the localised removed label once anonymised" do
    user = users(:player_one)
    user.update!(anonymized_at: Time.current)

    assert_equal "Removed player", user.display_name
    I18n.with_locale(:pt) { assert_equal "Jogador removido", user.reload.player.name }
  end
end
