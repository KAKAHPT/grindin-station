# frozen_string_literal: true

module Exports
  # EventLink invite list: one column, no header, the player's reporting e-mail or, for a guest, the name.
  module Players
    def self.call(event)
      rows = CsvFile.participants(event).map { |participant| [participant.player.reporting_email || participant.name] }
      CsvFile.generate(nil, rows.uniq)
    end
  end
end
