# frozen_string_literal: true

module Exports
  # CSV as Excel and the reporting tools read it: UTF-8 with a BOM, CRLF line ends. No header row when
  # headers is nil (the EventLink invite list).
  module CsvFile
    BOM = "﻿"

    def self.generate(headers, rows)
      body =
        CSV.generate(row_sep: "\r\n", encoding: Encoding::UTF_8) do |csv|
          csv << headers if headers
          rows.each { |row| csv << row.map { |cell| safe_cell(cell) } }
        end
      BOM + body
    end

    # A text cell that a spreadsheet would run as a formula (=, +, -, @, tab, CR) gets a leading quote.
    # Numbers and rates stay as they are; names and handles are free text and can start with any of those.
    FORMULA_START = /\A[=+\-@\t\r]/

    def self.safe_cell(cell)
      cell.is_a?(String) && cell.match?(FORMULA_START) ? "'#{cell}" : cell
    end

    # Rates as 0.000; blank when there is none yet (a player with byes only has no win rate).
    def self.rate(value) = value && format("%.3f", value)

    # Off-waitlist participants (dropped ones included: they played) with their players and users.
    def self.participants(event)
      event.event_participants.where(waitlisted: false).includes(player: :user).sort_by(&:name)
    end
  end
end
