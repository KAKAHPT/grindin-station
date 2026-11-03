# frozen_string_literal: true

module Results
  # A player's report, confirmation or contest was refused; the message is a key under
  # results.not_allowed in the locales.
  class NotAllowed < StandardError; end
end
