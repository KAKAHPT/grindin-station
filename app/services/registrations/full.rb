# frozen_string_literal: true

module Registrations
  # Registration refused: the event is full and has no waitlist.
  class Full < StandardError; end
end
