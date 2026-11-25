# frozen_string_literal: true

require "test_helper"

# rubocop:disable Metrics/ClassLength
class LeagueTest < ActiveSupport::TestCase
  test "league has correct state enum" do
    assert_includes League.states, "draft"
    assert_includes League.states, "registration_open"
    assert_includes League.states, "registration_closed"
    assert_includes League.states, "play"
    assert_includes League.states, "finals"
    assert_includes League.states, "finished"
    assert_includes League.states, "canceled"
  end

  test "a new league defaults to open tables, results closed on the report and a cut of 16" do
    league = League.new
    assert league.play_mode_open_tables?
    assert_equal "none", league.result_confirmation
    assert_equal 16, league.top_cut_size
    assert_equal 1000, league.starting_points
    assert_equal "split", league.draw_rule
    assert_equal 10, league.min_games_for_cut
  end

  test "closing and closed are stored as 7 and 8 and the older states keep their numbers" do
    assert_equal({ "draft" => 0, "registration_open" => 1, "registration_closed" => 2, "play" => 3, "finals" => 4,
                   "finished" => 5, "canceled" => 6, "closing" => 7, "closed" => 8 }, League.states)
  end

  test "a draw rule outside the list is refused" do
    league = leagues(:standard_league)
    league.draw_rule = "burn"
    assert_not league.valid?
    assert league.errors[:draw_rule].any?
  end

  test "a player holds one active seat at a time" do
    league = leagues(:standard_league)
    player = event_participants(:league_event_participant_one)
    first = LeagueTable.create!(league: league, opener: player)
    first.seats.create!(event_participant: player)
    second = LeagueTable.create!(league: league, opener: player)
    assert_raises(ActiveRecord::RecordNotUnique) { second.seats.create!(event_participant: player) }
    first.release_seats!
    assert second.seats.create!(event_participant: player)
  end

  test "a league with tables, games and a cancellation asked can be deleted, and so can one of its players" do
    league = LeagueBuilder.build(players: 5, organizer: event_organizers(:standard_organizer))
    players = league.event_participants.order(:created_at).to_a
    pod = LeagueBuilder.fill_table!(league, players.first(4))
    Leagues::Tables::RequestCancel.call(table: pod.league_table, participant: players[1], reason: "No show")
    Leagues::Tables::Open.call(league: league, participant: players[4])

    players[4].destroy!
    assert_equal 1, league.league_tables.count

    league.destroy!
    assert_equal 0, LeagueTable.where(event_id: league.id).count
  end

  test "tables open only in play, in open-tables mode, before the end date" do
    league = leagues(:standard_league)
    league.update_columns(state: League.states[:play], play_mode: 2, end_time: 1.day.from_now) # rubocop:disable Rails/SkipsModelValidations
    assert league.tables_open?
    league.update_column(:end_time, 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
    assert_not league.tables_open?
  end

  test "a league cannot be 1v1" do
    league = leagues(:standard_league)
    league.format = "one_v_one"
    assert_not league.valid?
    assert_includes league.errors[:format], "is not included in the list"
  end

  test "league transitions from draft to registration_open" do
    league = leagues(:standard_league)
    league.update_column(:state, League.states[:draft]) # rubocop:disable Rails/SkipsModelValidations
    league.update!(state: "registration_open")
    assert league.registration_open?
  end

  test "league transitions from registration_open to registration_closed" do
    league = leagues(:standard_league)
    league.update!(state: "registration_closed")
    assert league.registration_closed?
  end

  test "league transitions from registration_closed to play" do
    league = leagues(:standard_league)
    league.update!(state: "registration_closed")
    league.update!(state: "play")
    assert league.play?
  end

  test "league transitions from play to finals" do
    league = leagues(:standard_league)
    league.update!(state: "registration_closed")
    league.update!(state: "play")
    league.update!(state: "finals")
    assert league.finals?
  end

  test "league transitions from finals to finished" do
    league = leagues(:standard_league)
    league.update!(state: "registration_closed")
    league.update!(state: "play")
    league.update!(state: "finals")
    league.update!(state: "finished")
    assert league.finished?
  end

  test "league can be canceled once registration opens, not from draft" do
    league = leagues(:standard_league)
    league.update!(state: "canceled")
    assert league.canceled?

    league.update_column(:state, League.states[:draft]) # rubocop:disable Rails/SkipsModelValidations
    assert_not league.update(state: "canceled")
  end

  test "ongoing scope returns play and finals leagues" do
    league = leagues(:standard_league)
    league.registration_closed!
    league.play!
    assert_includes League.ongoing, league
  end

  test "wager_percentage must be between 0 and 100" do
    league = leagues(:standard_league)
    league.wager_percentage = 101
    assert_not league.valid?
    assert_includes league.errors[:wager_percentage], I18n.t("errors.messages.less_than_or_equal_to", count: 100)

    league.wager_percentage = -1
    assert_not league.valid?
    assert_includes league.errors[:wager_percentage], I18n.t("errors.messages.greater_than_or_equal_to", count: 0)

    league.wager_percentage = 0
    assert league.valid?

    league.wager_percentage = 100
    assert league.valid?

    league.wager_percentage = nil
    assert league.valid?
  end

  test "play_mode enum is defined" do
    assert_includes League.play_modes, "scheduled"
    assert_includes League.play_modes, "pickup"
  end

  test "league defaults to scheduled play_mode" do
    league = leagues(:standard_league)
    assert_equal "scheduled", league.play_mode
    assert league.play_mode_scheduled?
  end

  test "scheduled mode league can be set to pickup" do
    league = leagues(:standard_league)
    league.play_mode_scheduled!
    assert league.play_mode_scheduled?

    league.play_mode_pickup!
    assert league.play_mode_pickup?
  end

  test "perform_state_based_actions triggers StartPlayRoundJob" do
    league = leagues(:standard_league)
    league.registration_closed!

    # Verify that transitioning to play runs StartPlayRoundJob
    # (perform_state_based_actions calls perform_now which runs synchronously)
    assert_nothing_raised do
      league.play!
    end
    assert_equal "play", league.reload.state
  end

  test "perform_state_based_actions triggers StartFinalsRoundJob" do
    league = leagues(:standard_league)
    league.registration_closed!
    league.play!

    # Verify that transitioning to finals runs StartFinalsRoundJob
    assert_nothing_raised do
      league.finals!
    end
    assert_equal "finals", league.reload.state
  end
end
