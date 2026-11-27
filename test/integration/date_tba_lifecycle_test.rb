# frozen_string_literal: true

require "test_helper"

# A tournament created with its date to be announced, then given its real date, plays to the end like any other:
# the registrations, the check-in, the rounds, the final positions and the ranking season follow the real date.
class DateTbaLifecycleTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  PLAYERS = 8

  setup do
    post session_path,
         params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    @estimate = 3.months.from_now.change(usec: 0)
  end

  test "created to be announced, announced later, then played to the end" do
    tournament = create_tba_tournament
    assert_date_hidden(tournament)

    participants = enrol(tournament)
    announce(tournament, starts: 1.hour.from_now.change(usec: 0))

    assert_date_shown(tournament)
    assert_equal participants.map(&:id).sort, tournament.event_participants.ids.sort
    assert_predicate tournament, :check_in_open?

    play_to_the_end(tournament)

    assert_predicate tournament.reload, :finished?
    assert_equal (1..PLAYERS).to_a, tournament.event_participants.pluck(:final_position).sort
    seasons = RankingContribution.where(event_id: tournament.id).distinct.pluck(:season)
    assert_equal [tournament.start_time.year], seasons
    get play_standings_path(tournament.slug)
    assert_response :success
  end

  test "the date is announced while the swiss is already running" do
    tournament = create_tba_tournament
    enrol(tournament)
    start_swiss(tournament)
    pods = seatings_of(tournament)
    assert_date_hidden(tournament)

    announce(tournament, starts: 2.hours.ago.change(usec: 0))

    assert_date_shown(tournament)
    assert_equal pods, seatings_of(tournament)
    play_to_the_end(tournament)
    assert_predicate tournament.reload, :finished?
  end

  test "an announced date can go back to be announced, and the estimate can change, without losing anyone" do
    tournament = create_tba_tournament
    participants = enrol(tournament)
    announce(tournament, starts: 1.week.from_now.change(usec: 0))

    later = 5.months.from_now
    patch organizer_tournament_path(tournament),
          params: { tournament: { date_tba: "1", start_time: later, end_time: later + 8.hours } }

    assert_predicate tournament.reload, :date_tba
    assert_date_hidden(tournament)
    assert_equal participants.map(&:id).sort, tournament.event_participants.ids.sort
  end

  private

  def create_tba_tournament
    assert_difference -> { Tournament.count }, 1 do
      post organizer_tournaments_path, params: { tournament: {
        name: "Data por anunciar", game_format: "commander", date_tba: "1", start_time: @estimate,
        end_time: @estimate + 8.hours, state: "registration_open", swiss_rounds_count: 2, top_cut_size: 0
      } }
    end
    Tournament.order(:created_at).last.tap { |tournament| assert_predicate tournament, :date_tba }
  end

  def enrol(tournament)
    Array.new(PLAYERS) do |i|
      tournament.event_participants.create!(player_name: "Jogador #{i + 1}", accepted_terms: true,
                                            player_email: "tba-#{i + 1}-#{tournament.id}@example.com")
    end
  end

  def announce(tournament, starts:)
    patch organizer_tournament_path(tournament),
          params: { tournament: { date_tba: "0", start_time: starts, end_time: starts + 8.hours } }

    assert_redirected_to organizer_tournament_path(tournament)
    tournament.reload
    assert_not tournament.date_tba
    assert_equal starts, tournament.start_time
  end

  def start_swiss(tournament)
    perform_enqueued_jobs do
      patch organizer_tournament_path(tournament), params: { tournament: { state: "registration_closed" } }
      patch organizer_tournament_path(tournament), params: { tournament: { state: "swiss" } }
    end
    assert_predicate tournament.reload, :swiss?
  end

  def play_to_the_end(tournament)
    start_swiss(tournament) unless tournament.swiss?
    2.times { play_round(tournament, tournament.rounds.order(:number).last) }
  end

  def play_round(tournament, round)
    round.pods.each do |pod|
      post organizer_tournament_round_pod_results_path(tournament, round, pod),
           params: { result: { type: "Win", event_participant_id: pod.seatings.first.event_participant_id } }
    end
    clear_enqueued_jobs
    patch organizer_tournament_round_path(tournament, round), params: { round: { action: :close } }
    perform_enqueued_jobs
  end

  def seatings_of(tournament)
    pods = tournament.rounds.order(:number).last.pods.order(:number)
    pods.map { |pod| pod.seatings.order(:order).pluck(:event_participant_id) }
  end

  def day(tournament) = I18n.l(tournament.start_time, format: "%-d %b %Y")

  def assert_date_hidden(tournament)
    get play_event_path(tournament.slug)
    assert_response :success
    assert_select "[data-about] [data-date-tba]", count: 1
    assert_not_includes response.body, day(tournament)
    get "/api/v1/events/#{tournament.slug}/info"
    assert_nil response.parsed_body["starts_at"]
    assert_nil tournament.check_in_opens_at
  end

  def assert_date_shown(tournament)
    get play_event_path(tournament.slug)
    assert_response :success
    assert_select "[data-about] [data-date-tba]", count: 0
    assert_select ".evhead-line", text: /#{Regexp.escape(day(tournament))}/
    get "/api/v1/events/#{tournament.slug}/info"
    assert_equal tournament.start_time.utc.iso8601, response.parsed_body["starts_at"]
  end
end
