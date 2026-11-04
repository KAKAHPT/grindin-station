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

      delete organizer_tournament_round_path(@t, round2)

      assert_redirected_to organizer_tournament_round_path(@t, @round)
      assert_not Round.exists?(round2.id)
      assert_nil @round.reload.finished_at
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
