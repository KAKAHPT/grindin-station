# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Exports
  class MeleeTest < ActiveSupport::TestCase
    include ExportTournament

    setup { @t = build_export_tournament }

    test "Melee player import: e-mail, first and last name, display name = handle" do
      user = participant_named(@t, "Jogador 1").player.user
      user.update!(name: "Fábio de Batista")
      participant_named(@t, "Jogador 2").player.user.update!(name: "Cher")

      rows = nil
      without_n_plus_one { rows = parse_export(Exports::Melee.call(@t)) }

      assert_equal %w[Email FirstName LastName WizardsAccountDisplayName], rows.first
      assert_equal 17, rows.size
      assert_includes rows, [user.email_address, "Fábio", "de Batista", user.handle]
      cher = rows.find { |row| row[1] == "Cher" }
      assert_equal %w[Cher Cher], cher[1, 2]
    end
  end
end
