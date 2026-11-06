# frozen_string_literal: true

require "test_helper"

module Profiles
  class HistoryTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength -- one test per row field
    setup do
      @user = User.create!(name: "Rita Grind", email_address: "rita-#{SecureRandom.hex(3)}@example.com",
                           password: "password123")
    end

    test "lists finished events with position, field size, W-L-D and seats" do
      event = played_event(@user, position: 3, winner_seat: 0)

      rows = History.call(user: @user)

      assert_equal 1, rows.size
      row = rows.first
      assert_equal event, row.event
      assert_equal [3, 4], [row.position, row.participants]
      seat = event.event_participants.find_by(player: @user.player).seatings.first.order
      assert_equal 1, row.seats[seat]
      assert_equal 1, row.seats.values.sum
      assert_equal 1, row.wins + row.losses + row.draws
    end

    test "leaves out events that are not finished" do
      played_event(@user, position: 1, state: :swiss)

      assert_empty History.call(user: @user)
    end

    test "orders the events by date, newest first" do
      older = played_event(@user, position: 1, start_time: 2.months.ago)
      newer = played_event(@user, position: 2, start_time: 1.week.ago)

      assert_equal [newer, older], History.call(user: @user).map(&:event)
    end

    test "decklists are visible only when the event shows them" do
      hidden = played_event(@user, position: 1, start_time: 2.days.ago)
      shown = played_event(@user, position: 2, start_time: 1.day.ago, show_decklists: true)
      [hidden, shown].each do |event|
        event.event_participants.find_by(player: @user.player).update!(decklist: "https://moxfield.com/decks/x")
      end

      visible = History.call(user: @user).to_h { |row| [row.event, row.decklist_visible] }

      assert_equal({ shown => true, hidden => false }, visible)
    end

    test "a user without a player has no history" do
      @user.player.destroy!

      assert_empty History.call(user: @user.reload)
    end

    test "a top-4 cut: made the cut, cut size, seats by swiss round, commander, season and format" do
      cut = { top_cut_size: 4, circuit_id: circuits(:standard_circuit).id, rounds: 2 }
      event =
        played_event(@user, position: 2, winner_seat: 0, **cut) do |t|
          participant(t, @user).update!(decklist: "Kinnan, Bonder Prodigy")
          t.rounds.create!(type: SingleEliminationRound, number: 3)
        end
      seats = Seating.joins(pod: :round).where(rounds: { type: "SwissRound" })
        .where(event_participant: participant(event, @user)).order("rounds.number").pluck(:order)

      row = History.call(user: @user).first

      assert row.made_cut
      assert_equal 4, row.cut_size
      assert_equal seats, row.round_seats
      assert_equal 2, row.round_seats.size
      assert_equal "Kinnan, Bonder Prodigy", row.commander
      assert_equal "Standard Circuit", row.season
      assert_equal event.event_organizer.name, row.organizer_name
      assert_equal I18n.t("play.header.multiplayer"), row.format_line
      assert_equal row.wins + row.losses + row.draws, row.games
    end

    test "no cut, no circuit and a link for a decklist: nil cut size, season and commander" do
      played_event(@user, position: 1) do |tournament|
        participant(tournament, @user).update!(decklist: "https://moxfield.com/decks/x")
      end

      row = History.call(user: @user).first

      assert_not row.made_cut
      assert_nil row.cut_size
      assert_nil row.season
      assert_nil row.commander
    end

    test "an Advance in a single-elimination round without a seat there counts as making the cut" do
      played_event(@user, position: 1, top_cut_size: 4) do |tournament|
        cut = tournament.rounds.create!(type: SingleEliminationRound, number: 2)
        user_participant = participant(tournament, @user)
        Seating.where(pod: cut.pods, event_participant: user_participant).destroy_all
        Result.where(round: cut, event_participant: user_participant).destroy_all
        Advance.create!(round: cut, event_participant: user_participant)
      end

      assert History.call(user: @user).first.made_cut
    end

    test "1v1 events have no round seats and a Bo line" do
      played_event(@user, position: 1, format: "one_v_one")

      row = History.call(user: @user).first

      assert_nil row.round_seats
      assert_equal "Standard · Bo3", row.format_line
    end

    test "the number of queries does not grow with the number of events" do
      circuit = circuits(:standard_circuit).id
      played_event(@user, position: 1, start_time: 3.days.ago, top_cut_size: nil, circuit_id: circuit)
      one = queries_of { History.call(user: @user) }
      played_event(@user, position: 2, start_time: 2.days.ago, top_cut_size: 4, circuit_id: circuit) do |tournament|
        tournament.rounds.create!(type: SingleEliminationRound, number: 2)
      end
      played_event(@user, position: 3, start_time: 1.day.ago, top_cut_size: nil)
      played_event(@user, position: 4, format: "one_v_one")

      assert_equal 4, History.call(user: @user).size
      assert_equal one, queries_of { History.call(user: @user) } # rubocop:disable Lint/AmbiguousBlockAssociation
    end

    private

    def participant(event, user) = event.event_participants.find_by(player: user.player)

    # SQL statements run by the block, the query cache off so a repeated statement still counts.
    def queries_of(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      ActiveRecord::Base.uncached { ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block) }
      count
    end

    # A 4-player tournament with the user in it, `rounds` swiss rounds played (default 1), then put in `state`.
    # `format` goes to the builder; other attrs are written on the event. The block runs before the state
    # change (to add a cut round or a decklist).
    def played_event(user, position:, state: :finished, winner_seat: :draw, **attrs)
      event = event_with(user, format: attrs.delete(:format) || "multiplayer")
      rounds = attrs.delete(:rounds) || 1
      event.update_columns(swiss_rounds_count: rounds, top_cut_size: 0, **attrs) # rubocop:disable Rails/SkipsModelValidations
      rounds.times { |i| play_swiss_round(event, i + 1, winner_seat) }
      yield event if block_given?
      participant(event, user).update_columns(final_position: position) # rubocop:disable Rails/SkipsModelValidations
      event.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
      event.reload
    end

    def event_with(user, format:)
      event = TournamentBuilder.build(players: 3, organizer: event_organizers(:standard_organizer), state: :swiss,
                                      format: format)
      event.event_participants.create!(player: user.player, accepted_terms: true)
      event
    end

    def play_swiss_round(event, number, winner_seat)
      event.rounds.create!(type: SwissRound, number: number)
      TournamentBuilder.play_round!(event, winners: { 1 => winner_seat })
    end
  end
end
