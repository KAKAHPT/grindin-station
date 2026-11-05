# frozen_string_literal: true

require "test_helper"

class EventTierTest < ActiveSupport::TestCase
  setup do
    @event = TournamentBuilder.build(players: 0, organizer: event_organizers(:standard_organizer), state: :draft)
  end

  test "tier defaults to none and accepts the listed tiers" do
    assert_equal "none", @event.tier
    Event::TIERS.each do |tier|
      @event.tier = tier
      assert @event.valid?, tier
    end
  end

  test "rejects an unknown tier" do
    @event.tier = "diamond"

    assert_not @event.valid?
    assert @event.errors.added?(:tier, :inclusion, value: "diamond")
  end

  test "multipliers per tier" do
    assert_equal({ "none" => 0, "bronze" => 1, "silver" => 1.5, "gold" => 2, "platinum" => 3 }, Event::TIER_MULTIPLIERS)
  end

  test "country is two letters, upcased, blank is nil" do
    @event.update!(country: " pt ")
    assert_equal "PT", @event.reload.country

    @event.update!(country: "")
    assert_nil @event.reload.country
  end

  test "rejects a country that is not two letters" do
    @event.country = "Portugal"

    assert_not @event.valid?
    assert_predicate @event.errors[:country], :present?
  end
end
