# frozen_string_literal: true

require "test_helper"

# Query volume of the busiest pages at 64 players after one round (Prosopite catches N+1s;
# this keeps the totals flat as the field grows).
class QueryBudgetTest < ActionDispatch::IntegrationTest
  setup do
    @t = TournamentBuilder.build(players: 64, organizer: event_organizers(:standard_organizer))
    @t.update_columns(swiss_rounds_count: 3, top_cut_size: 16) # rubocop:disable Rails/SkipsModelValidations
    @round = @t.rounds.create!(type: SwissRound, number: 1)
    @round.update_columns(started_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    TournamentBuilder.play_round!(@t, winners: (1..16).index_with { |n| n.even? ? :draw : 0 })
    post session_path,
         params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
  end

  test "roster runs under 60 queries" do
    assert_queries_under(60, "roster") { get organizer_tournament_event_participants_path(@t, layout: "application") }
  end

  test "roster modal runs under 60 queries" do
    assert_queries_under(60, "roster modal") { get organizer_tournament_event_participants_path(@t) }
  end

  test "round page runs under 60 queries" do
    assert_queries_under(60, "round page") { get organizer_tournament_round_path(@t, @round) }
  end

  test "public round page runs under 60 queries" do
    assert_queries_under(60, "public round page") { get tournament_round_path(@t, @round) }
  end

  test "public standings run under 60 queries" do
    assert_queries_under(60, "public standings") { get tournament_event_participants_path(@t) }
  end

  test "public event page with a waitlist runs under 60 queries" do
    10.times do |i|
      user = User.create!(name: "Espera #{i}", email_address: "espera-#{i}-#{SecureRandom.hex(3)}@example.com",
                          password: "password123")
      @t.event_participants.create!(player: user.player, accepted_terms: true, waitlisted: true,
                                    waitlist_position: i + 1)
    end
    assert_queries_under(60, "event page (organizer)") { get play_event_path(@t.slug) }
    assert_select "[data-enrolled] li", count: 64
    assert_select "[data-waitlist] li", count: 10

    delete session_path
    assert_queries_under(60, "event page (visitor)") { get play_event_path(@t.slug) }
  end

  private

  def assert_queries_under(limit, label, &block)
    count = count_queries(&block)
    assert_response :success
    puts "\n[query budget] #{label}: #{count}" if ENV["QUERY_BUDGET_REPORT"]
    assert_operator count, :<, limit, "#{label} ran #{count} queries"
  end

  def count_queries(&block)
    count = 0
    counter =
      lambda do |_name, _start, _finish, _id, payload|
        count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached]
      end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
