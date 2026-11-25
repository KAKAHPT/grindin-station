# frozen_string_literal: true

module Leagues
  module Tables
    # A player's action on a league table was refused; the message is the key of the reason
    # (leagues.tables.not_allowed.<key>).
    class NotAllowed < StandardError; end
  end
end
