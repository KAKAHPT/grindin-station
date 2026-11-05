# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Exports
  class CsvFileTest < ActiveSupport::TestCase
    test "writes a BOM, the header and CRLF rows, quoting as needed" do
      csv = Exports::CsvFile.generate(%w[a b], [[1, "x, y"], [nil, "z"]])

      assert_equal "﻿a,b\r\n1,\"x, y\"\r\n,z\r\n", csv
    end

    test "without headers writes only the rows" do
      assert_equal "﻿one\r\ntwo\r\n", Exports::CsvFile.generate(nil, [["one"], ["two"]])
    end
  end
end
