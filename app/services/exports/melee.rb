# frozen_string_literal: true

module Exports
  # Melee player import. First name = the name's first word, last name = the rest (the first word again
  # for a one-word name), display name = the handle.
  module Melee
    HEADERS = %w[Email FirstName LastName WizardsAccountDisplayName].freeze

    def self.call(event)
      rows =
        CsvFile.participants(event).map do |participant|
          first, last = participant.name.strip.split(/\s+/, 2)
          [participant.player.reporting_email, first, last || first, participant.player.user&.handle]
        end
      CsvFile.generate(HEADERS, rows)
    end
  end
end
