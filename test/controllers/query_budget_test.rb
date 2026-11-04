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

  test "the old public round page redirects to the round's pairings" do
    @round.update!(published: true)
    get tournament_round_path(@t, @round)
    assert_redirected_to play_pairings_path(@t.slug, round: 1)
  end

  test "public standings run under 60 queries" do
    assert_queries_under(60, "public standings") { get play_standings_path(@t.slug) }
  end

  test "public pairings with 16 tables run under 60 queries" do
    @t.rounds.create!(type: SwissRound, number: 2).update!(published: true)
    assert_queries_under(60, "public pairings (organizer)") { get play_pairings_path(@t.slug) }
    assert_select "[data-pod-number]", count: 16

    delete session_path
    assert_queries_under(60, "public pairings (visitor)") { get play_pairings_path(@t.slug) }
    assert_queries_under(60, "public pairings, closed round") { get play_pairings_path(@t.slug, round: 1) }
  end

  test "pairings and standings for a signed-in enrolled player run under 60 queries" do
    @t.rounds.create!(type: SwissRound, number: 2).update!(published: true)
    player = @t.rounds.find_by!(number: 2).seatings.first.event_participant.player.user
    player.update!(password: "password123")
    delete session_path
    post session_path, params: { session: { email_address: player.email_address, password: "password123" } }

    assert_queries_under(60, "public pairings (player)") { get play_pairings_path(@t.slug) }
    assert_select "[data-my-table]", count: 1
    assert_queries_under(60, "public standings (player)") { get play_standings_path(@t.slug) }
    assert_select "tr[data-me]", count: 1
  end

  test "public event page with a waitlist runs under 60 queries" do
    10.times do |i|
      user = User.create!(name: "Espera #{i}", email_address: "espera-#{i}-#{SecureRandom.hex(3)}@example.com",
                          password: "password123")
      @t.event_participants.create!(player: user.player, accepted_terms: true, waitlisted: true,
                                    waitlist_position: i + 1)
    end
    assert_queries_under(60, "event page (organizer)") { get play_event_path(@t.slug) }
    assert_select "[data-counters]", text: /64 players enrolled.*10 on the waiting list/m

    delete session_path
    assert_queries_under(60, "event page (visitor)") { get play_event_path(@t.slug) }
  end

  test "stream feeds of a 64-player, 5-round event run under 15 queries each" do
    @t.update_columns(swiss_rounds_count: 5) # rubocop:disable Rails/SkipsModelValidations
    (2..5).each do |number|
      @t.rounds.create!(type: SwissRound, number: number)
      TournamentBuilder.play_round!(@t, winners: (1..16).index_with { |n| n.even? ? :draw : 0 })
    end
    delete session_path

    %w[standings rounds info].each do |feed|
      ActiveRecord::Base.connection.clear_query_cache # each feed counted cold
      assert_queries_under(15, "feed #{feed}") { get "/api/v1/events/#{@t.slug}/#{feed}" }
    end
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
