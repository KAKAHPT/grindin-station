# frozen_string_literal: true

require "test_helper"

module Admin
  class HealthTest < ActiveSupport::TestCase
    setup do
      @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
      @round = @tournament.rounds.create!(type: "SwissRound", number: 1)
      @start = Time.zone.local(2026, 11, 5, 10, 0)
      @round.update_columns(started_at: @start) # rubocop:disable Rails/SkipsModelValidations
    end

    test "a round is late only past its start plus duration plus the largest extra time" do
      @round.pods.first.update_columns(extra_time: 10) # rubocop:disable Rails/SkipsModelValidations

      travel_to(@start + 85.minutes) { assert_not row.late }
      travel_to(@start + 91.minutes) { assert row.late }
    end

    test "a finished round is never late" do
      @round.update_columns(finished_at: @start + 60.minutes) # rubocop:disable Rails/SkipsModelValidations

      travel_to(@start + 5.hours) { assert_not row.late }
    end

    test "a round without a duration (the last cut round) is never late" do
      @tournament.update_columns(top_cut_size: 4) # rubocop:disable Rails/SkipsModelValidations
      last = @tournament.number_of_swiss_rounds + @tournament.number_of_single_elimination_rounds
      Round.where(id: @round.id).update_all(type: "SingleEliminationRound", number: last) # rubocop:disable Rails/SkipsModelValidations

      travel_to(@start + 10.hours) { assert_not row.late }
    end

    private

    def row
      Health.call.find { |r| r.event == @tournament }
    end
  end
end
