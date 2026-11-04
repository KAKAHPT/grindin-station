# frozen_string_literal: true

require "test_helper"

module Tournaments
  class FinishTournamentJobTest < ActiveJob::TestCase
    test "job runs without errors" do
      tournament = events(:small_tournament)

      assert_nothing_raised do
        Tournaments::FinishTournamentJob.perform_now(tournament)
      end
    end

    test "job is queued with correct arguments" do
      tournament = events(:small_tournament)

      assert_enqueued_with(job: Tournaments::FinishTournamentJob, args: [tournament]) do
        Tournaments::FinishTournamentJob.perform_later(tournament)
      end
    end

    test "a top 4 played to the end records unique final positions, winner first, finalists 2-4" do
      tournament, final = top_four_played_to_the_end
      winner = final.seatings.find_by!(order: 2).event_participant
      finalists = final.seatings.map(&:event_participant)
      dropped = (tournament.event_participants.where(waitlisted: false) - finalists).first
      dropped.update!(dropped: true)
      waiting = waitlist!(tournament)

      Tournaments::FinishTournamentJob.perform_now(tournament)

      positions = tournament.event_participants.where(waitlisted: false).pluck(:id, :final_position).to_h
      assert_equal (1..16).to_a, positions.values.sort
      assert_equal 1, positions[winner.id]
      assert_equal [2, 3, 4], (finalists - [winner]).map { |p| positions[p.id] }.sort
      assert_equal 16, positions[dropped.id]
      assert_nil waiting.reload.final_position

      dropped.update!(dropped: false)
      Tournaments::FinishTournamentJob.perform_now(tournament)
      assert_equal (1..16).to_a, tournament.event_participants.where(waitlisted: false).pluck(:final_position).sort
      assert_operator dropped.reload.final_position, :<, 16
    end

    test "circuit points are awarded from the final positions" do
      tournament, final = top_four_played_to_the_end
      circuit = circuits(:standard_circuit)
      tournament.update_column(:circuit_id, circuit.id) # rubocop:disable Rails/SkipsModelValidations
      winner = final.seatings.find_by!(order: 2).event_participant

      Tournaments::FinishTournamentJob.perform_now(tournament.reload)

      assert_equal 16, circuit.circuit_standings.count
      assert_in_delta 16.0, circuit.circuit_standings.find_by!(player: winner.player).points
    end

    private

    def top_four_played_to_the_end
      tournament = TournamentBuilder.build(players: 16, organizer: event_organizers(:standard_organizer))
      tournament.update_columns(swiss_rounds_count: 1, top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      tournament.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(tournament, winners: { 1 => 0, 2 => 1, 3 => :draw, 4 => 3 })
      [tournament.reload, play_final!(tournament)]
    end

    # The seat-2 player wins the final (Advance); the other three are eliminated.
    def play_final!(tournament)
      final = tournament.rounds.create!(type: SingleEliminationRound, number: 2)
      final.pods.sole.seatings.each do |seating|
        result = seating.order == 2 ? Advance : Eliminated
        result.create!(round: final, event_participant_id: seating.event_participant_id)
      end
      final.update_columns(finished_at: Time.current, published: true) # rubocop:disable Rails/SkipsModelValidations
      final
    end

    def waitlist!(tournament)
      tournament.event_participants.create!(player_name: "Espera", accepted_terms: true, waitlisted: true,
                                            waitlist_position: 1,
                                            player_email: "espera-#{SecureRandom.hex(3)}@example.com")
    end
  end
end
