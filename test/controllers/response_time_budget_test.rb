# frozen_string_literal: true

require "test_helper"

# Response time of the pages a whole room opens at once (64 players, top cut running): the best of three
# requests must stay under the budget. The query budgets (query_budget_test) keep the cause flat; this keeps
# the effect, the time a player waits, under a ceiling.
class ResponseTimeBudgetTest < ActionDispatch::IntegrationTest
  BUDGET_MS = Integer(ENV.fetch("RESPONSE_TIME_BUDGET_MS", 200))

  setup do
    @t = TournamentBuilder.build(players: 64, organizer: event_organizers(:standard_organizer))
    @t.update_columns(swiss_rounds_count: 1, top_cut_size: 16) # rubocop:disable Rails/SkipsModelValidations
    @t.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(@t, winners: (1..16).index_with { |n| n.even? ? :draw : 0 })
    @t.rounds.create!(type: SingleEliminationRound, number: 2).update!(published: true)
  end

  test "the public pages answer within the budget" do
    {
      "event page" => play_event_path(@t.slug),
      "swiss pairings" => play_pairings_path(@t.slug, round: 1),
      "top-cut bracket" => play_pairings_path(@t.slug),
      "standings" => play_standings_path(@t.slug),
      "standings feed" => "/api/v1/events/#{@t.slug}/standings"
    }.each do |label, path|
      get path # warm-up: template compilation is not what a player waits for
      assert_response :success
      best = Array.new(3) { elapsed_ms { get path } }.min
      puts "\n[time budget] #{label}: #{best.round} ms" if ENV["QUERY_BUDGET_REPORT"]
      assert_operator best, :<, BUDGET_MS, "#{label} took #{best.round} ms"
    end
  end

  private

  def elapsed_ms
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
  end
end
