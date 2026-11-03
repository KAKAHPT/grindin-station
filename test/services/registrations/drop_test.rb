# frozen_string_literal: true

require "test_helper"

module Registrations
  class DropTest < ActiveSupport::TestCase
    setup do
      @organizer = users(:organizer_user)
    end

    test "a no-show is dropped with its reason and time" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_closed)
      participant = tournament.event_participants.first

      Drop.call(participant: participant, reason: "no_show", by: @organizer)

      participant.reload
      assert participant.dropped?
      assert_equal "no_show", participant.drop_reason
      assert_not_nil participant.dropped_at
    end

    test "dropping before the start promotes the first on the waitlist and renumbers the rest" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open)
      tournament.update!(maximum_participants: 4, waitlist_enabled: true)
      first = Enroll.call(event: tournament, player: players(:player_one))
      second = Enroll.call(event: tournament, player: players(:player_two))

      Drop.call(participant: tournament.event_participants.where(waitlisted: false).first, by: @organizer)

      assert_not first.reload.waitlisted?
      assert_nil first.waitlist_position
      assert_equal 1, second.reload.waitlist_position
      assert_equal 4, tournament.reload.playing_participants_count
    end

    test "dropping after the start promotes no one" do
      tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                           state: :registration_open)
      tournament.update!(maximum_participants: 4, waitlist_enabled: true)
      waiting = Enroll.call(event: tournament, player: players(:player_one))
      tournament.update_column(:state, "swiss") # rubocop:disable Rails/SkipsModelValidations
      tournament.reload.rounds.create!(type: SwissRound, number: 1).update!(published: true)

      Drop.call(participant: tournament.event_participants.where(waitlisted: false).first, by: @organizer)

      assert waiting.reload.waitlisted?
    end

    test "a drop after the round is published keeps the seat, takes a Loss and is not paired next round" do
      tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      round = tournament.rounds.create!(type: SwissRound, number: 1)
      round.update!(published: true)
      pod = round.pods.order(:number).first
      dropped, winner = pod.seatings.order(:order).map(&:event_participant).first(2)

      Drop.call(participant: dropped, by: @organizer)

      assert pod.seatings.reload.exists?(event_participant_id: dropped.id)
      Events::SubmitResultJob.perform_now(type: "Win", event_participant: winner, round: round, pod: pod)
      assert_instance_of Loss, Result.find_by(round: round, event_participant: dropped)

      TournamentBuilder.play_round!(tournament, winners: { 2 => 0 })
      next_round = tournament.reload.rounds.create!(type: SwissRound, number: 2)
      assert_not_includes next_round.seatings.map(&:event_participant_id), dropped.id
      assert_equal 7, next_round.seatings.count
    end

    test "a drop before the round is published rebuilds the round without the player" do
      tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      round = tournament.rounds.create!(type: SwissRound, number: 1)
      dropped = round.seatings.first.event_participant

      Drop.call(participant: dropped, by: @organizer)

      assert_not Round.exists?(round.id)
      rebuilt = tournament.reload.rounds.max_by(&:number)
      assert_not_includes rebuilt.seatings.map(&:event_participant_id), dropped.id
    end

    test "rejects an unknown reason" do
      participant = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                            state: :registration_closed).event_participants.first

      assert_raises(ActiveRecord::RecordInvalid) { Drop.call(participant: participant, reason: "bored", by: @organizer) }
    end
  end
end
