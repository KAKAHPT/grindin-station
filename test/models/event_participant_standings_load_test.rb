# frozen_string_literal: true

require "test_helper"

# EventParticipant.standings_for computes the same standings as one participant at a time.
class EventParticipantStandingsLoadTest < ActiveSupport::TestCase
  test "the shared load matches the per-participant standings" do
    t = TournamentBuilder.build(players: 12, organizer: event_organizers(:standard_organizer))
    t.update_columns(swiss_rounds_count: 3, top_cut_size: 0, seed: 7) # rubocop:disable Rails/SkipsModelValidations
    t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(t, winners: { 1 => 0, 2 => :draw, 3 => 2 })
    t.rounds.create!(type: SwissRound, number: 2)
    TournamentBuilder.play_round!(t, winners: { 1 => 1, 2 => 3, 3 => :draw })
    t.rounds.create!(type: SwissRound, number: 3).update!(published: true)

    loaded = EventParticipant.standings_for(t.reload).index_by(&:id)

    t.event_participants.each do |participant|
      fresh = EventParticipant.find(participant.id)
      shared = loaded.fetch(participant.id)
      assert_equal fresh.standing_columns, shared.standing_columns
      assert_equal fresh.rank_score, shared.rank_score
      assert_equal fresh.opponents.map(&:id).sort, shared.opponent_records.map(&:id).sort
    end
  end
end
