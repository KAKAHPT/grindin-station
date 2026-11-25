# frozen_string_literal: true

require "test_helper"

# An infraction given at a table must not block deleting that table or its event.
class PodInfractionsTest < ActiveSupport::TestCase
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    round = @tournament.rounds.create!(type: SwissRound, number: 1)
    @pod = round.pods.first
    player = @pod.seatings.first.event_participant.player
    @infraction = Infraction.create!(event: @tournament, player: player, pod: @pod, description: "Slow play")
  end

  test "deleting the table keeps the infraction without a table" do
    @pod.destroy!

    assert_nil @infraction.reload.pod_id
  end

  test "an event with an infraction given at a table can be deleted" do
    @tournament.destroy!

    assert_not Tournament.exists?(@tournament.id)
    assert_not Infraction.exists?(@infraction.id)
  end
end
