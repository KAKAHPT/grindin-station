# frozen_string_literal: true

module Registrations
  # Registration refused: the event is by invitation and this player was not invited.
  class NotInvited < StandardError; end
end
