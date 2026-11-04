# frozen_string_literal: true

require "test_helper"

# The tournament pages of a 1v1 event: "Table N" with two names and no seat squares, the score next to
# the winner, and the 1v1 standings columns (OMW%, GW%, OGW%; no Seats, Beaten or Unique).
class OneVOnePagesTest < ActionDispatch::IntegrationTest
  ONE_V_ONE_COLUMNS = ["Rank", "Player", "Pts", "OMW%", "GW%", "OGW%", "Win %", "W-L-D"].freeze

  setup do
    @t = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), format: "one_v_one")
    @t.update_columns(swiss_rounds_count: 3, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    @round = @t.rounds.create!(type: SwissRound, number: 1)
    @round.update!(published: true, started_at: Time.current)
    TournamentBuilder.play_1v1_round!(@t, scores: { 1 => [2, 1], 2 => [1, 1] })
    @pod = @round.pods.find_by!(number: 1)
    @winner, @loser = @pod.seatings.order(:order).map(&:event_participant)
  end

  test "public pairings: two names per table, no seat squares, the score next to the winner" do
    get play_pairings_path(@t.slug)

    assert_response :success
    assert_select "li[data-seat]", 0
    assert_select "[data-pod-number='1'] li[data-participant-id]", 2
    assert_select "[data-pod-number='1'] li[data-winner]", text: /#{@winner.name}.*2-1/m
  end

  test "my table: the table number big, the opponent, no seat" do
    sign_in(@loser.player.user)
    get play_me_path(@t.slug)

    assert_response :success
    assert_select "[data-table-number]", text: "1"
    assert_select "[data-seat-number]", 0
    assert_select "#my_table li", 2
    assert_select "#my_table li > span:first-child", text: /\A\s*\d\s*\z/, count: 0
    assert_select "#my_table li:not([data-me])", text: /#{@winner.name}.*2-1/m
  end

  test "organizer round page: no seat squares on the pod card" do
    sign_in(users(:organizer_user))
    get organizer_tournament_round_path(@t, @round)

    assert_response :success
    assert_select "#pod_#{@pod.id} li[data-name]", 2
    assert_select "#pod_#{@pod.id} li > span:first-child", text: /\A\s*\d\s*\z/, count: 0
  end

  test "print and slips: two names per table, no seat numbers" do
    sign_in(users(:organizer_user))

    [print_organizer_tournament_round_path(@t, @round),
     slips_organizer_tournament_round_path(@t, @round)].each do |path|
      get path

      assert_response :success
      assert_select ".seat-no", 0
      assert_select "h2", text: "Table 1"
      assert_select ".seat-name", 4
    end
  end

  test "public standings: the 1v1 columns and help, no seat grid" do
    get play_standings_path(@t.slug)

    assert_response :success
    assert_equal(ONE_V_ONE_COLUMNS, css_select("thead th").map { |th| th.text.strip })
    assert_select "tbody tr", 4
    assert_select "tbody span[role=img]", 0
    assert_select "p", text: I18n.t("standings.help.omw")
    assert_select "p", text: I18n.t("standings.help.ogw")
    assert_select "p", text: I18n.t("standings.help.beaten"), count: 0
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(@winner)} td", text: "66.7%"
  end

  test "organizer standings and roster desk: the 1v1 columns, no seat grid" do
    sign_in(users(:organizer_user))

    get organizer_tournament_event_participants_path(@t)
    assert_response :success
    assert_equal(ONE_V_ONE_COLUMNS, css_select("thead th").map { |th| th.text.strip })
    assert_select "tbody span[role=img]", 0

    get organizer_tournament_event_participants_path(@t, layout: "application")
    assert_response :success
    assert_select "thead th", text: "OMW%"
    assert_select "thead th", text: "OWR", count: 0
    assert_select "tbody span[role=img]", 0
    assert_select "tbody tr[id^=stats_]", text: /GW%/
    assert_select "tbody tr[id^=stats_]", text: /Seats/, count: 0
  end

  test "event page: the format badge" do
    get play_event_path(@t.slug)
    assert_select "[data-event-format]", text: "1v1 · Bo3"

    @t.update_column(:match_games, 1) # rubocop:disable Rails/SkipsModelValidations
    get play_event_path(@t.slug)
    assert_select "[data-event-format]", text: "1v1 · Bo1"

    multiplayer = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    get play_event_path(multiplayer.slug)
    assert_select "[data-event-format]", 0
  end

  test "profile history: a 1v1 event has no seats" do
    user = @winner.player.user
    user.update!(handle: "grinder-#{SecureRandom.hex(3)}", visibility: "public")
    @winner.update_columns(final_position: 1) # rubocop:disable Rails/SkipsModelValidations
    @t.update_column(:state, :finished) # rubocop:disable Rails/SkipsModelValidations

    get profile_path(user.handle)

    assert_response :success
    assert_select "[data-profile-event]", 1 do
      assert_select "[data-wld]", text: "1-0-0"
      assert_select "span[role=img]", 0
    end
  end

  private

  def sign_in(user)
    user.update!(password: "password123")
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
  end
end
