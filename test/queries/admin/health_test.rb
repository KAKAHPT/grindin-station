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

    test "cut rounds of several tournaments follow the model's durations without N+1 queries" do
      cut_rounds = Array.new(2) { |i| cut_round(last: i.zero?) }

      travel_to(@start + 4.hours) do
        Prosopite.scan
        rows = Health.call.index_by(&:event)
        Prosopite.finish

        assert_not rows.fetch(cut_rounds.first.event).late, "the last cut round has no duration"
        assert rows.fetch(cut_rounds.last.event).late, "an earlier cut round is late past top_cut_round_minutes"
        assert_nil cut_rounds.first.duration
        assert_equal 150.minutes, cut_rounds.last.duration
      end
    end

    test "a league play round is never late" do
      league = League.create!(name: "Liga", event_organizer: event_organizers(:standard_organizer), state: :draft,
                              start_time: @start, end_time: @start + 30.days)
      league.update_column(:state, League.states[:play]) # rubocop:disable Rails/SkipsModelValidations
      Round.insert!({ event_id: league.id, type: "SwissRound", number: 1, is_play_round: true, started_at: @start }) # rubocop:disable Rails/SkipsModelValidations

      travel_to(@start + 3.days) { assert_not(Health.call.find { |r| r.event == league }.late) }
    end

    private

    # A started single elimination round, the last of its tournament's cut or the one before it.
    def cut_round(last:)
      tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                           state: :single_elimination)
      tournament.update_columns(top_cut_size: 16) # rubocop:disable Rails/SkipsModelValidations
      final = tournament.number_of_swiss_rounds + tournament.number_of_single_elimination_rounds
      round = tournament.rounds.create!(type: "SwissRound", number: 1)
      Round.where(id: round.id).update_all(type: "SingleEliminationRound", number: last ? final : final - 1, # rubocop:disable Rails/SkipsModelValidations
                                           started_at: @start)
      Round.find(round.id)
    end

    def row
      Health.call.find { |r| r.event == @tournament }
    end
  end
end
