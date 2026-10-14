# frozen_string_literal: true

require "test_helper"

class EventPointsTest < ActiveSupport::TestCase
  test "defaults are 7/1/0/7" do
    t = Tournament.new
    assert_equal [7, 1, 0, 7], [t.points_win, t.points_draw, t.points_loss, t.points_bye]
  end

  test "match points use the event's values" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.update_columns(points_win: 5, points_draw: 2) # rubocop:disable Rails/SkipsModelValidations
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0 })
    winner = t.rounds.first.pods.first.event_participants.first
    assert_equal 5, winner.reload.match_points
  end

  test "points are locked once the swiss starts" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.points_win = 9
    assert_not t.valid?
    assert_includes t.errors[:points_win], I18n.t("activerecord.errors.models.event.attributes.points_win.locked")
  end

  test "reload clears memoized standings values" do
    participant = event_participants(:small_event_participant_one) # 1 win
    assert_equal 7, participant.match_points
    participant.event.update_columns(points_win: 3) # rubocop:disable Rails/SkipsModelValidations
    assert_equal 3, participant.reload.match_points
  end

  test "points stay editable before the swiss starts" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :registration_closed)
    t.points_win = 9
    assert t.valid?, t.errors.full_messages.to_sentence
  end
end
