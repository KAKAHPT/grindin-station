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

  test "a handle taken between validation and insert retries with the next suffix" do
    racing(times: 1) do
      user = create_user("Fábio Batista", "fabio@example.com")

      assert user.persisted?
      assert_equal "fabio-batista-2", user.handle
      assert user.player.present?
    end
  end

  test "the retry is bounded" do
    racing(times: 3) do
      assert_raises(ActiveRecord::RecordNotUnique) { create_user("Fábio Batista", "fabio@example.com") }
    end
  end

  test "a duplicate name signs up without an N+1 on handles" do
    2.times { |i| create_user("Same Name", "same#{i}@example.com") }
    Prosopite.scan
    create_user("Same Name", "same2@example.com")
    Prosopite.finish

    assert_equal "same-name-3", User.find_by(email_address: "same2@example.com").handle
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

  private

  # Another sign-up takes the chosen handle right before the insert, `times` times (inside the
  # same savepoint, as a concurrent commit would look to the insert).
  def racing(times:)
    races = 0
    test_case = self # the callback runs on the user
    racer = ->(user) { test_case.send(:take_handle, user.handle, races += 1) if races < times }
    User.set_callback(:create, :before, racer)
    yield
  ensure
    User.skip_callback(:create, :before, racer)
  end

  def take_handle(handle, number)
    User.insert!({ name: "Racer", email_address: "racer#{number}@example.com", handle: handle, # rubocop:disable Rails/SkipsModelValidations
                   password_digest: "x" })
  end
end
