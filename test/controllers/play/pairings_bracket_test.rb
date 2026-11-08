# frozen_string_literal: true

require "test_helper"

module Play
  # The public pairings page during the top cut: the whole cut as a vertical bracket.
  class PairingsBracketTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 32, organizer: event_organizers(:standard_organizer))
      @tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 13) # rubocop:disable Rails/SkipsModelValidations
      @tournament.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(@tournament, winners: (1..8).index_with(0))
      @cut = @tournament.rounds.create!(type: SingleEliminationRound, number: 2)
      @cut.update!(published: true)
    end

    test "a cut round shows every stage of the cut: the played one with its tables and byes, the rest empty" do
      get play_pairings_path(@tournament.slug)

      assert_response :success
      assert_select "[data-pairings]", count: 0
      assert_select "[data-bracket][data-controller=bracket][data-bracket-open-value='2']" do
        assert_select "[data-bracket-stage]", count: 2
        assert_select "[data-bracket-stage='2']" do
          assert_select "h2", text: "Semi-Finals"
          assert_select "[data-stage-status=upcoming]", count: 1
          assert_select "[data-byes][data-bracket-card] li[data-participant-id=?]", @cut.byes.sole.event_participant_id
          assert_select "article[data-pairing-table][data-bracket-card]", count: 3
          assert_select "[data-placeholder-table]", count: 0
        end
        assert_select "[data-bracket-stage='3']" do
          assert_select "h2", text: "Finals"
          assert_select "[data-placeholder-table][data-bracket-card]", count: 1 do
            assert_select "h3", text: "Table 1"
            assert_select "li", count: 4
          end
        end
        assert_select "[data-bracket-target=tabs] button[data-action='bracket#open']", count: 2
        assert_select "svg[data-bracket-target=wires] path"
      end
    end

    test "once the final is paired both stages show real tables; ?round=N picks the stage opened on phones" do
      @cut.update!(started_at: 30.minutes.ago)
      TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => 0, 3 => 0 })
      final = @tournament.rounds.create!(type: SingleEliminationRound, number: 3)
      final.update!(published: true, started_at: Time.current)

      get play_pairings_path(@tournament.slug)

      assert_select "[data-bracket][data-bracket-open-value='3']" do
        assert_select "[data-bracket-stage='2'] [data-stage-status=finished]", count: 1
        assert_select "[data-bracket-stage='3'] [data-stage-status=running]", count: 1
        assert_select "[data-bracket-stage='3'] article[data-pairing-table]", count: 1
        assert_select "[data-placeholder-table]", count: 0
      end

      get play_pairings_path(@tournament.slug, round: 2)

      assert_select "[data-bracket][data-bracket-open-value='2']"
    end

    test "a 1v1 cut draws two-player tables without seat squares" do
      tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                           format: "one_v_one")
      tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      tournament.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_1v1_round!(tournament, scores: (1..4).index_with([2, 0]))
      tournament.rounds.create!(type: SingleEliminationRound, number: 2).update!(published: true)

      get play_pairings_path(tournament.slug)

      assert_select "[data-bracket-stage='2'] article[data-pairing-table]", count: 2
      assert_select "[data-bracket-stage='3'] [data-placeholder-table]", count: 1 do
        assert_select "li", count: 2
        assert_select "li span.size-\\[22px\\]", count: 0
      end
    end

    test "a swiss round keeps the plain grid" do
      get play_pairings_path(@tournament.slug, round: 1)

      assert_select "[data-pairings]"
      assert_select "[data-bracket]", count: 0
    end
  end
end
