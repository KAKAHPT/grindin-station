# frozen_string_literal: true

require "test_helper"

module Profiles
  class HistoryTest < ActiveSupport::TestCase
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

    private

    # A 4-player tournament with the user in it, one swiss round played, then put in `state`.
    def played_event(user, position:, state: :finished, winner_seat: :draw, **attrs)
      event = TournamentBuilder.build(players: 3, organizer: event_organizers(:standard_organizer), state: :swiss)
      event.event_participants.create!(player: user.player, accepted_terms: true)
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 0, **attrs) # rubocop:disable Rails/SkipsModelValidations
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(event, winners: { 1 => winner_seat })
      event.event_participants.find_by(player: user.player).update_columns(final_position: position) # rubocop:disable Rails/SkipsModelValidations
      event.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
      event.reload
    end
  end
end
