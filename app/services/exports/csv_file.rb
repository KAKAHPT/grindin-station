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
          rows.each { |row| csv << row }
        end
      BOM + body
    end

    # Rates as 0.000; blank when there is none yet (a player with byes only has no win rate).
    def self.rate(value) = value && format("%.3f", value)

    # Off-waitlist participants (dropped ones included: they played) with their players and users.
    def self.participants(event)
      event.event_participants.where(waitlisted: false).includes(player: :user).sort_by(&:name)
    end
  end
end
