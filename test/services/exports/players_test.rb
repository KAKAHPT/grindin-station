# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Exports
  class PlayersTest < ActiveSupport::TestCase
    include ExportTournament

    setup do
      @t = build_export_tournament
      participant_named(@t, "Jogador 2").player.update!(wizards_email: "Wizards2@Example.com")
      @guest = participant_named(@t, "Jogador 3").player
      @guest.update_column(:user_id, nil) # rubocop:disable Rails/SkipsModelValidations
    end

    test "one column, no header: the reporting e-mail, else the name, one line per player" do
      rows = nil
      without_n_plus_one { rows = parse_export(Exports::Players.call(@t)) }

      assert_equal 16, rows.size
      assert(rows.all? { |row| row.size == 1 && row.first.present? })
      emails = rows.flatten
      assert_includes emails, "wizards2@example.com"
      assert_includes emails, @guest.reload.name
      assert_includes emails, participant_named(@t, "Jogador 1").player.user.email_address
      assert_not_includes emails, "Jogador 1"
    end

    test "the waitlist never played and is left out" do
      participant_named(@t, "Jogador 4").update_column(:waitlisted, true) # rubocop:disable Rails/SkipsModelValidations

      assert_equal 15, parse_export(Exports::Players.call(@t)).size
    end
  end
end
