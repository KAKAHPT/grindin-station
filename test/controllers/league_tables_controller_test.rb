# frozen_string_literal: true

require "test_helper"

class LeagueTablesControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  setup do
    @league = LeagueBuilder.build(players: 5, organizer: event_organizers(:standard_organizer))
    @players = @league.event_participants.order(:created_at).to_a
    @users =
      @players.map do |participant|
        user = User.create!(name: participant.name, email_address: "conta-#{SecureRandom.hex(4)}@example.com",
                            password: "password123", confirmed_at: Time.current)
        participant.update!(player: user.player)
        user
      end
  end

  test "a visitor sees the tables tab without buttons" do
    Leagues::Tables::Open.call(league: @league, participant: @players[0])

    get league_path(@league, tab: "tables")

    assert_response :success
    assert_select "[data-waiting-table]", 1
    assert_select "[data-waiting-table] form", 0
    assert_select "[data-waiting-table] a[data-join-sign-in][href=?]", new_session_path
    assert_select "[data-tables-visitor]"
    get league_path(@league)
    assert_select "[data-league-rounds]", 0
  end

  test "four players fill a table, the winner reports and the standings follow" do # rubocop:disable Metrics/BlockLength
    as(0) { post league_tables_path(@league) }
    table = @league.league_tables.sole
    as(1) do
      get league_path(@league, tab: "tables")
      assert_select "[data-waiting-table] form[action=?]", join_league_table_path(@league, table)
      assert_select "[data-waiting-table] li", 1
      post join_league_table_path(@league, table)
    end
    as(2) { post join_league_table_path(@league, table) }
    as(3) do
      post join_league_table_path(@league, table)
      assert_redirected_to league_path(@league, tab: "mine")
      follow_redirect!
      assert_select "[data-my-table=filled] [data-report-form]"
      assert_select "[data-report=win]"
      assert_select "[data-report=draw]"
      post report_league_table_path(@league, table), params: { result: @players[0].id }
      assert_equal I18n.t("results.not_allowed.invalid_type"), flash[:alert]
      post report_league_table_path(@league, table), params: { result: "win" }
      assert_redirected_to league_path(@league, tab: "played")
    end
    as(1) do
      get league_path(@league, tab: "tables")
      assert_select "[data-go-to-mine]", 0
    end
    as(0) do
      get league_path(@league, tab: "mine")
      assert_select "[data-no-table]"
      get league_path(@league, tab: "played")
      assert_select "[data-correction-open]"
      post correction_league_table_path(@league, table), params: { reason: "" }
      assert_equal I18n.t("leagues.tables.not_allowed.reason_required"), flash[:alert]
      post correction_league_table_path(@league, table), params: { reason: "Player 1 won" }
      follow_redirect!
      assert_select "[data-correction=pending]"
      assert_select "[data-correction-open]", 0
    end
    get league_path(@league, tab: "played")
    assert_select "[data-league-played] [data-winner]", 1

    assert_equal([900, 900, 900, 1300, 1000], @players.map { |player| player.reload.league_score.to_i })
    as(3) do
      get league_path(@league)
      assert_select "[data-league-me] [data-league-rank]", text: "#1"
      assert_select "[data-league-me] [data-league-record]", text: /1W · 0L · 0D/
      assert_select "[data-league-me] [data-league-win-rate]", text: "100%"
    end
    get league_path(@league)
    assert_select "[data-league-me]", 0
    get league_path(@league, tab: "standings")
    assert_select "[data-league-row]:first-child td", text: @players[3].name
    as(0) do
      get league_path(@league, tab: "tables")
      assert_select "[data-open-table]"
    end
  end

  test "leaving, closing and the refusals show their message" do
    as(0) { post league_tables_path(@league) }
    table = @league.league_tables.sole
    as(1) do
      post join_league_table_path(@league, table)
      post close_league_table_path(@league, table)
      assert_equal I18n.t("leagues.tables.not_allowed.not_opener"), flash[:alert]
      post leave_league_table_path(@league, table)
      assert_equal 1, table.reload.participants.size
    end
    as(0) do
      post league_tables_path(@league)
      assert_equal I18n.t("leagues.tables.not_allowed.busy"), flash[:alert]
      post close_league_table_path(@league, table)
    end
    assert_predicate table.reload, :closed?
  end

  test "asking to cancel needs a reason; the clock starts once" do
    pod = LeagueBuilder.fill_table!(@league, @players.first(4))
    table = pod.league_table
    as(0) do
      post cancel_league_table_path(@league, table), params: { reason: " " }
      assert_equal I18n.t("leagues.tables.not_allowed.reason_required"), flash[:alert]
      post cancel_league_table_path(@league, table), params: { reason: "Two players had to leave" }
      follow_redirect!
      assert_select "[data-cancel-state=pending]"
      post clock_league_table_path(@league, table)
    end
    started = pod.reload.clock_started_at
    assert_not_nil started
    as(1) { post clock_league_table_path(@league, table) }
    assert_equal started, pod.reload.clock_started_at
    as(4) do
      post clock_league_table_path(@league, table)
      assert_equal I18n.t("leagues.tables.not_allowed.not_member"), flash[:alert]
    end
  end

  test "my events shows the table I am at, leading to the league's tables" do
    LeagueBuilder.fill_table!(@league, @players.first(4))
    as(0) do
      get my_events_path
      assert_select "[data-my-league-tables] a[href=?]", league_path(@league, tab: "mine")
    end
    as(4) do
      get my_events_path
      get league_path(@league, tab: "mine")
      assert_select "[data-no-table]"
      assert_select "[data-my-league-tables]", 0
    end
  end

  test "signing in is required to act" do
    post league_tables_path(@league)

    assert_redirected_to new_session_path
  end

  private

  def as(index)
    post session_path, params: { session: { email_address: @users[index].email_address, password: "password123" } }
    yield
    delete session_path
  end
end
