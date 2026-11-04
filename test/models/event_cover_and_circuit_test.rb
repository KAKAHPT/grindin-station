# frozen_string_literal: true

require "test_helper"

class EventCoverAndCircuitTest < ActiveSupport::TestCase
  setup do
    @league = leagues(:standard_league)
  end

  test "an event cannot join another organizer's circuit" do
    other = User.create!(name: "Other", email_address: "other-org@example.com", password: "password123",
                         organizer: true).event_organizer
    foreign = Circuit.create!(name: "Foreign", event_organizer: other)

    assert_not @league.update(circuit_id: foreign.id)
    assert @league.errors.added?(:circuit, :other_organizer)
    assert @league.update(circuit: circuits(:standard_circuit))
  end

  test "the cover must be a JPEG, PNG or WebP image" do
    @league.cover.attach(io: StringIO.new("GIF89a"), filename: "a.gif", content_type: "image/gif")

    assert_not @league.valid?
    assert @league.errors.added?(:cover, :content_type)
  end

  test "the cover must be 4 MB or smaller" do
    @league.cover.attach(io: StringIO.new("x" * (4.megabytes + 1)), filename: "big.jpg", content_type: "image/jpeg")

    assert_not @league.valid?
    assert @league.errors.added?(:cover, :too_big)
  end

  test "a JPEG cover is accepted" do
    @league.cover.attach(io: file_fixture("cover1.jpg").open, filename: "cover1.jpg", content_type: "image/jpeg")

    assert_predicate @league, :valid?
  end
end
