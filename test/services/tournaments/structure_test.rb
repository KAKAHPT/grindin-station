# frozen_string_literal: true

require "test_helper"

module Tournaments
  class StructureTest < ActiveSupport::TestCase
    test "suggestions follow the spec table" do
      expected = { 4 => [3, 0], 7 => [3, 4], 8 => [4, 4], 23 => [4, 4], 24 => [4, 10], 31 => [4, 10],
                   32 => [4, 13], 39 => [4, 13], 40 => [5, 16], 63 => [5, 16], 64 => [6, 16], 127 => [6, 16],
                   128 => [7, 40] }
      expected.each do |n, (rounds, cut)|
        s = Tournaments::Structure.suggested(n)
        assert_equal [rounds, cut], [s[:swiss_rounds], s[:top_cut_size]], "for #{n} players"
      end
    end

    test "1v1 suggestions follow MTR Appendix E" do
      expected = { 3 => [0, 0], 4 => [0, 4], 7 => [0, 4], 8 => [0, 8], 9 => [5, 4], 16 => [5, 4], 17 => [5, 8],
                   33 => [6, 8], 65 => [7, 8], 129 => [8, 8], 227 => [9, 8], 410 => [10, 8] }
      expected.each do |n, (rounds, cut)|
        s = Tournaments::Structure.suggested(n, format: "one_v_one")
        assert_equal [rounds, cut], [s[:swiss_rounds], s[:top_cut_size]], "for #{n} players"
      end
      assert_equal({ swiss_rounds: 3, top_cut_size: 0 }, Tournaments::Structure.suggested(4, format: "multiplayer"))
    end

    test "tournament rejects a cut bigger than the field" do
      t = TournamentBuilder.build(players: 12, organizer: event_organizers(:standard_organizer),
                                  state: :registration_closed)
      t.top_cut_size = 16
      assert_not t.valid?
      assert_includes t.errors[:top_cut_size],
                      I18n.t("activerecord.errors.models.event.attributes.top_cut_size.too_big")
    end

    test "rounds_info strategies: 1 standard, 2 spread, last forced" do
      t = TournamentBuilder.build(players: 40, organizer: event_organizers(:standard_organizer))
      assert_equal(%i[standard spread standard standard forced], t.rounds_info[:rounds].pluck(:swiss_round))
      assert_equal({ players: 16, pods: [4, 1] }, t.rounds_info[:top])
    end
  end
end
