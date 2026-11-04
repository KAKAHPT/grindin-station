# frozen_string_literal: true

require "test_helper"

module Organizer
  class RoundUndoTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
      @t = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @t.update_columns(swiss_rounds_count: 2, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      @round = @t.rounds.create!(type: SwissRound, number: 1)
      @round.update_columns(published: true, started_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    test "undoing a later round removes it and reopens the previous one" do
      TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => 0 })
      round2 = @t.rounds.create!(type: SwissRound, number: 2)

      ::Standings::Snapshot.call(@t, @round)

      delete organizer_tournament_round_path(@t, round2)

      assert_redirected_to organizer_tournament_round_path(@t, @round)
      assert_not Round.exists?(round2.id)
      assert_nil @round.reload.finished_at
      assert_not @t.standings_snapshots.exists?
    end

    test "undoing the first cut round goes back to the swiss and reopens its last round" do
      TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => 0 })
      @t.rounds.create!(type: SwissRound, number: 2)
      round2 = TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => 0 })
      @t.update_column(:state, Tournament.states[:single_elimination]) # rubocop:disable Rails/SkipsModelValidations
      cut = @t.rounds.create!(type: SingleEliminationRound, number: 3)

      [@round, round2].each { |round| ::Standings::Snapshot.call(@t, round) }

      delete organizer_tournament_round_path(@t, cut)

      assert_redirected_to organizer_tournament_round_path(@t, round2)
      assert_not Round.exists?(cut.id)
      assert_nil round2.reload.finished_at
      assert_predicate @t.reload, :swiss?
      assert_equal [1], @t.standings_snapshots.distinct.pluck(:round_number)
    end

    test "an older round cannot be undone while a later one exists" do
      TournamentBuilder.play_round!(@t, winners: { 1 => 0, 2 => 0 })
      round2 = @t.rounds.create!(type: SwissRound, number: 2)

      delete organizer_tournament_round_path(@t, @round)

      assert_redirected_to organizer_tournament_round_path(@t, @round)
      assert_equal I18n.t("rounds.cannot_undo_older"), flash[:alert]
      assert Round.exists?(@round.id)
      assert Round.exists?(round2.id)
    end

    test "the only round cannot be undone and offers no undo button" do
      get organizer_tournament_round_path(@t, @round)
      assert_select "button", text: I18n.t("rounds.undo"), count: 0

      delete organizer_tournament_round_path(@t, @round)

      assert_redirected_to organizer_tournament_round_path(@t, @round)
      assert_equal I18n.t("rounds.cannot_undo_first"), flash[:alert]
      assert Round.exists?(@round.id)
      assert_predicate @t.reload, :swiss?
    end
  end
end
