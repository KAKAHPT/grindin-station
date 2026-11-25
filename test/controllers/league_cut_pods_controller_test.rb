# frozen_string_literal: true

require "test_helper"

# Players report their own table of a league's top cut on the league page.
class LeagueCutPodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @league = LeagueBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                  min_games_for_cut: 1, top_cut_size: 4)
    @players = @league.event_participants.order(:created_at).to_a
    @players.each_slice(4) do |four|
      pod = LeagueBuilder.fill_table!(@league, four)
      Results::Apply.call(pod: pod, type: "Win", winner: four.first)
    end
    Leagues::Lifecycle.close(@league, by: nil)
    Leagues::Lifecycle.make_cut(@league.reload, by: nil)
    @round = LeagueCutRound.find_by!(event: @league)
    @pod = @round.pods.sole
    @seated = @pod.seatings.order(:order).map(&:event_participant)
  end

  test "the cut table shows on the league page and its winner closes it with I won" do
    winner = sign_in_as_participant(@seated.first)

    get league_path(@league, tab: "tables")
    assert_select "[data-cut-round] [data-cut-pod]", 1
    assert_select "[data-cut-report]", 0
    assert_select "[data-go-to-mine]"
    get league_path(@league, tab: "mine")
    assert_select "[data-cut-pod][data-my-table] [data-cut-report] form[action=?]", report_league_cut_pod_path(@league, @pod)

    post report_league_cut_pod_path(@league, @pod)

    assert_redirected_to league_path(@league, tab: "mine")
    assert_kind_of Advance, @round.results.find_by(event_participant: winner)
    assert_equal 4, @round.results.where(event_participant: @seated).count
    assert_nil @round.reload.finished_at, "the organizer still closes the round"
    follow_redirect!
    assert_select "[data-cut-report]", 0
    get league_path(@league, tab: "tables")
    assert_select "[data-cut-pod][data-cut-done=true] li[data-winner]", 1
  end

  test "a second report, or one from outside the table, is refused" do
    sign_in_as_participant(@seated.first)
    post report_league_cut_pod_path(@league, @pod)
    delete session_path
    sign_in_as_participant(@seated.second)

    post report_league_cut_pod_path(@league, @pod)

    assert_equal I18n.t("results.not_allowed.already_finished"), flash[:alert]
    assert_kind_of Eliminated, @round.results.find_by(event_participant: @seated.second)

    outsider = (@players - @seated).first
    @round.results.where(event_participant: @seated).destroy_all
    delete session_path
    sign_in_as_participant(outsider)
    post report_league_cut_pod_path(@league, @pod)
    assert_equal I18n.t("results.not_allowed.not_seated"), flash[:alert]
    assert_equal 0, @round.results.where(event_participant: @seated).count
  end

  private

  def sign_in_as_participant(participant)
    user = User.create!(name: participant.name, email_address: "corte-#{SecureRandom.hex(4)}@example.com",
                        password: "password123", confirmed_at: Time.current)
    participant.update!(player: user.player)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    participant
  end
end
