# frozen_string_literal: true

require "test_helper"

class DecklistLockTest < ActionDispatch::IntegrationTest
  setup do
    @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    @participant = @tournament.event_participants.first
    user = @participant.player.user
    user.update!(password: "password123")
    sign_in(user)
  end

  test "a player edits the decklist until round 1 is published" do
    patch tournament_event_participant_path(@tournament, @participant),
          params: { event_participant: { decklist: "Kinnan" } }
    assert_equal "Kinnan", @participant.reload.decklist

    @tournament.rounds.create!(type: SwissRound, number: 1).update!(published: true)
    get edit_tournament_event_participant_path(@tournament, @participant)
    assert_equal I18n.t("flash.alert.decklist_locked"), flash[:alert]

    patch tournament_event_participant_path(@tournament, @participant),
          params: { event_participant: { decklist: "Thrasios" } }
    assert_redirected_to tournament_path(@tournament)
    assert_equal I18n.t("flash.alert.decklist_locked"), flash[:alert]
    assert_equal "Kinnan", @participant.reload.decklist
  end

  test "staff still change the decklist after round 1 is published" do
    @tournament.rounds.create!(type: SwissRound, number: 1).update!(published: true)
    sign_in(users(:organizer_user))

    patch organizer_tournament_event_participant_path(@tournament, @participant),
          params: { event_participant: { decklist: "Tymna" } }

    assert_equal "Tymna", @participant.reload.decklist
  end

  private

  def sign_in(user)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
