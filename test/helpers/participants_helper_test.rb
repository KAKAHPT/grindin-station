# frozen_string_literal: true

require "test_helper"

class ParticipantsHelperTest < ActionView::TestCase
  test "the commander text, never a web address" do
    participant = EventParticipant.new(decklist: "Kinnan, Bonder Prodigy")
    assert_equal "Kinnan, Bonder Prodigy", commander_text(participant)

    participant.decklist = "HTTPS://moxfield.com/decks/x"
    assert_nil commander_text(participant)

    participant.decklist = " "
    assert_nil commander_text(participant)
  end
end
