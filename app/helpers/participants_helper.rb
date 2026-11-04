# frozen_string_literal: true

module ParticipantsHelper
  # The decklist field as commander text for public pages; nil when blank or a web address, so a
  # decklist link never goes public before the event allows it.
  def commander_text(participant)
    text = participant.decklist.to_s.strip
    text unless text.empty? || text.match?(%r{\A(https?://|www\.|[a-z0-9-]+\.[a-z]{2,}(/|\z))}i)
  end
end
