# frozen_string_literal: true

require "test_helper"

class EventFormatTest < ActiveSupport::TestCase
  def points(event) = [event.points_win, event.points_draw, event.points_loss, event.points_bye]

  test "default format is multiplayer with 7/1/0/7" do
    t = Tournament.new
    assert_equal "multiplayer", t.format
    assert t.multiplayer?
    assert_not t.one_v_one?
    assert_equal [7, 1, 0, 7], points(t)
    assert_equal 3, t.match_games
  end

  test "a new one_v_one tournament defaults to 3/1/0/3" do
    t = Tournament.new(format: "one_v_one")
    assert t.one_v_one?
    assert_equal [3, 1, 0, 3], points(t)
  end

  test "explicit points are kept on a one_v_one tournament" do
    t = Tournament.new(format: "one_v_one", points_win: 7)
    assert_equal [7, 1, 0, 3], points(t)
  end

  test "format must be known" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.format = "duel"
    assert_not t.valid?
    assert t.errors.of_kind?(:format, :inclusion)
  end

  test "match_games must be 1 or 3" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.match_games = 2
    assert_not t.valid?
    assert t.errors.of_kind?(:match_games, :inclusion)
    [1, 3].each do |games|
      t.match_games = games
      assert t.valid?
    end
  end

  test "format is locked once a round exists" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.rounds.create!(type: SwissRound, number: 1)
    t.format = "one_v_one"
    assert_not t.valid?
    assert t.errors.of_kind?(:format, :locked)
  end

  test "format can change before any round exists" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    t.format = "one_v_one"
    assert t.valid?, t.errors.full_messages.to_sentence
  end

  test "Result#game_points is 3 per game won and 1 per game drawn" do
    assert_equal 6, Result.new(games_won: 2, games_lost: 1, games_drawn: 0).game_points
    assert_equal 4, Result.new(games_won: 1, games_lost: 1, games_drawn: 1).game_points
  end

  test "Result#games lists won, lost and drawn" do
    assert_equal [2, 1, 0], Result.new(games_won: 2, games_lost: 1).games
  end
end
