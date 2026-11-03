# frozen_string_literal: true

require "test_helper"

module Registrations
  class EnrollTest < ActiveSupport::TestCase
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                            state: :registration_open)
    end

    test "enrolls a player while there is room" do
      participant = Enroll.call(event: @tournament, player: players(:player_one), decklist: "https://moxfield.com/x")

      assert participant.persisted?
      assert_not participant.waitlisted?
      assert_equal "https://moxfield.com/x", participant.decklist
      assert_equal 5, @tournament.reload.playing_participants_count
    end

    test "refuses once the swiss has started" do
      @tournament.update_column(:state, "swiss") # rubocop:disable Rails/SkipsModelValidations

      assert_raises(Closed) { Enroll.call(event: @tournament.reload, player: players(:player_one)) }
    end

    test "waitlists when full, with increasing positions, outside the count" do
      @tournament.update!(maximum_participants: 4, waitlist_enabled: true)

      first = Enroll.call(event: @tournament, player: players(:player_one))
      second = Enroll.call(event: @tournament, player: players(:player_two))

      assert first.waitlisted?
      assert_equal 1, first.waitlist_position
      assert second.waitlisted?
      assert_equal 2, second.waitlist_position
      assert_equal 4, @tournament.reload.playing_participants_count
    end

    test "refuses when full and the waitlist is off" do
      @tournament.update!(maximum_participants: 4)

      assert_raises(Full) { Enroll.call(event: @tournament, player: players(:player_one)) }
    end

    test "waitlisted players are never paired" do
      @tournament.update!(maximum_participants: 4, waitlist_enabled: true)
      waiting = Enroll.call(event: @tournament, player: players(:player_one))
      @tournament.update_column(:state, "swiss") # rubocop:disable Rails/SkipsModelValidations

      round = @tournament.reload.rounds.create!(type: SwissRound, number: 1)

      assert_not_includes round.seatings.map(&:event_participant_id), waiting.id
      assert_equal 4, round.seatings.count
    end
  end
end
