# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Exports
  class CsvFileTest < ActiveSupport::TestCase
    test "writes a BOM, the header and CRLF rows, quoting as needed" do
      csv = Exports::CsvFile.generate(%w[a b], [[1, "x, y"], [nil, "z"]])

      assert_equal "﻿a,b\r\n1,\"x, y\"\r\n,z\r\n", csv
    end

    test "a text cell that would run as a formula gets a leading quote; numbers stay numbers" do
      out = Exports::CsvFile.generate(%w[name pts], [["=1+1", 7], ["+cmd", "0.500"], ["-x", "@y"], ["ok", "\tz"]])

      assert_includes out, "'=1+1,7\r\n"
      assert_includes out, "'+cmd,0.500\r\n"
      assert_includes out, "'-x,'@y\r\n"
      assert_includes out, "ok,'\tz\r\n"
    end

    test "without headers writes only the rows" do
      assert_equal "﻿one\r\ntwo\r\n", Exports::CsvFile.generate(nil, [["one"], ["two"]])
    end
  end
end
