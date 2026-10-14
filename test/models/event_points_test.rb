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

  test "a swiss bye counts as a played round in match win percentage" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    winner, loser = t.event_participants.first(2)
    round_one = finished_swiss_round(t, 1)
    round_two = finished_swiss_round(t, 2)
    Win.create!(round: round_one, event_participant: winner)
    Loss.create!(round: round_one, event_participant: loser)
    [winner, loser].each { |participant| Advance.create!(round: round_two, event_participant: participant) }

    assert_equal [1, 1], [winner.reload.number_of_byes, winner.number_of_wins]
    assert_equal 14, winner.match_points
    assert_in_delta 1.0, winner.match_win_percentage
    assert_in_delta 0.5, loser.reload.match_win_percentage
  end

  test "opponents' match win percentage is floored at the draw value" do
    { [7, 1] => 1.0 / 7, [5, 2] => 0.4 }.each do |(win, draw), floor|
      t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      t.update_columns(points_win: win, points_draw: draw) # rubocop:disable Rails/SkipsModelValidations
      t.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(t, winners: { 1 => 0 })
      winner = t.rounds.first.pods.first.event_participants.first

      assert_in_delta floor, winner.reload.opponents_average_match_win_percentage
    end
  end

  test "points_win must be at least 1" do
    t = Tournament.new(name: "Zero", points_win: 0)
    assert_not t.valid?
    assert_includes t.errors[:points_win], I18n.t("errors.messages.greater_than_or_equal_to", count: 1)
  end

  private

  # A finished, published swiss round with no pods, so an Advance in it is a bye (see Round#byes).
  def finished_swiss_round(tournament, number)
    SwissRound.insert!({ event_id: tournament.id, number: number, type: "SwissRound", # rubocop:disable Rails/SkipsModelValidations
                         started_at: 1.hour.ago, finished_at: Time.current, published: true })
    tournament.rounds.find_by!(number: number)
  end
end
