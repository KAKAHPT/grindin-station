# frozen_string_literal: true

require "test_helper"

class EventFormatTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
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
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :registration_open)
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

  test "format is chosen at creation and locked afterwards, even before any round" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                state: :registration_open)
    t.format = "one_v_one"
    assert_not t.valid?
    assert t.errors.of_kind?(:format, :locked)
    assert Tournament.new(format: "one_v_one").errors.none?
  end

  test "match_games is locked once the swiss starts" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                state: :registration_open, format: "one_v_one")
    t.match_games = 1
    assert t.valid?, t.errors.full_messages.to_sentence

    t.update_column(:state, :swiss) # rubocop:disable Rails/SkipsModelValidations
    t.match_games = 1
    assert_not t.valid?
    assert t.errors.of_kind?(:match_games, :locked)
    I18n.with_locale(:pt) { assert_includes t.errors.full_messages.to_sentence, "não pode mudar" }
  end

  test "a 1v1 tournament needs a 1v1 game format" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                state: :registration_open, format: "one_v_one")
    t.game_format = "commander"
    assert_not t.valid?
    assert t.errors.of_kind?(:game_format, :one_v_one)
    assert_includes t.errors.full_messages.to_sentence, "Format must be a 1v1 format"

    t.game_format = "chess"
    assert_not t.valid?
    assert t.errors.of_kind?(:game_format, :inclusion)

    t.game_format = "legacy"
    assert t.valid?, t.errors.full_messages.to_sentence
  end

  test "a multiplayer tournament is always commander" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :registration_open)
    assert_equal "commander", t.game_format
    t.update!(game_format: "legacy")
    assert_equal "commander", t.reload.game_format
  end

  test "play is multiplayer for pods and the game format for 1v1" do
    pods = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    duel = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), format: "one_v_one")
    duel.update_column(:game_format, "legacy") # rubocop:disable Rails/SkipsModelValidations

    assert_equal "multiplayer", pods.play
    assert_equal "legacy", duel.play
    assert_equal %w[multiplayer standard pioneer modern legacy vintage pauper], Event::PLAYS
  end

  test "with_play picks the pods or one 1v1 game format" do
    organizer = event_organizers(:standard_organizer)
    pods = TournamentBuilder.build(players: 4, organizer: organizer)
    legacy = TournamentBuilder.build(players: 4, organizer: organizer, format: "one_v_one")
    modern = TournamentBuilder.build(players: 4, organizer: organizer, format: "one_v_one")
    legacy.update_column(:game_format, "legacy") # rubocop:disable Rails/SkipsModelValidations
    modern.update_column(:game_format, "modern") # rubocop:disable Rails/SkipsModelValidations
    ids = [pods, legacy, modern].map(&:id)

    assert_equal [legacy.id], Tournament.where(id: ids).with_play("legacy").ids
    assert_equal [pods.id], Tournament.where(id: ids).with_play("multiplayer").ids
  end

  test "game_format is locked once the swiss starts" do
    t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                state: :swiss, format: "one_v_one")
    t.game_format = "pauper"
    assert_not t.valid?
    assert t.errors.of_kind?(:game_format, :locked)
  end

  test "Result#game_points is 3 per game won and 1 per game drawn" do
    assert_equal 6, Result.new(games_won: 2, games_lost: 1, games_drawn: 0).game_points
    assert_equal 4, Result.new(games_won: 1, games_lost: 1, games_drawn: 1).game_points
  end

  test "Result#games lists won, lost and drawn" do
    assert_equal [2, 1, 0], Result.new(games_won: 2, games_lost: 1).games
  end
end
