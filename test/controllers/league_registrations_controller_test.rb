# frozen_string_literal: true

require "test_helper"

class LeagueRegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @organizer = event_organizers(:standard_organizer)
    @league = LeagueBuilder.build(players: 4, organizer: @organizer, state: :registration_open, starting_points: 500)
    @user = User.create!(name: "Nova Jogadora", email_address: "nova-#{SecureRandom.hex(4)}@example.com",
                         password: "password123", confirmed_at: Time.current)
  end

  test "a visitor is sent to sign in, a signed-in player sees the form and registers" do
    get league_path(@league)
    assert_select "[data-league-registration] [data-registration=sign_in] a[href=?]", new_session_path

    sign_in
    get league_path(@league, tab: "tables")
    assert_select "[data-tables-visitor] form[data-registration=open][action=?]", league_registration_path(@league)

    post league_registration_path(@league), params: { accepted_terms: "1" }

    assert_redirected_to league_path(@league)
    participant = @league.event_participants.find_by!(player: @user.player)
    assert_predicate participant, :enrolled?
    assert_equal 500, participant.league_score.to_i
    follow_redirect!
    assert_select "[data-registration=enrolled]"
  end

  test "the rules must be accepted" do
    sign_in

    assert_no_difference -> { @league.event_participants.count } do
      post league_registration_path(@league)
    end
    assert_equal I18n.t("leagues.registration.accept_terms"), flash[:alert]
  end

  test "a league in play still takes players; a closed one does not" do
    @league.update_column(:state, League.states.fetch("play")) # rubocop:disable Rails/SkipsModelValidations
    sign_in
    post league_registration_path(@league), params: { accepted_terms: "1" }
    assert @league.event_participants.exists?(player: @user.player)

    other = LeagueBuilder.build(players: 4, organizer: @organizer, state: :closing)
    post league_registration_path(other), params: { accepted_terms: "1" }
    assert_equal I18n.t("flash.alert.registration_closed"), flash[:alert]
    assert_not other.event_participants.exists?(player: @user.player)
  end

  test "leaving before the start removes the registration" do
    sign_in
    post league_registration_path(@league), params: { accepted_terms: "1" }

    delete league_registration_path(@league)

    assert_not @league.event_participants.exists?(player: @user.player)
  end

  test "leaving a league in play is a drop that closes the table the player opened" do
    @league.update_column(:state, League.states.fetch("play")) # rubocop:disable Rails/SkipsModelValidations
    sign_in
    post league_registration_path(@league), params: { accepted_terms: "1" }
    participant = @league.event_participants.find_by!(player: @user.player)
    table = Leagues::Tables::Open.call(league: @league, participant: participant)

    delete league_registration_path(@league)

    assert_predicate participant.reload, :dropped?
    assert_predicate table.reload, :closed?
    get league_path(@league)
    assert_select "[data-registration=dropped]"
  end

  test "a player at a full table cannot leave until it is finished" do
    @league.update_column(:state, League.states.fetch("play")) # rubocop:disable Rails/SkipsModelValidations
    sign_in
    post league_registration_path(@league), params: { accepted_terms: "1" }
    participant = @league.event_participants.find_by!(player: @user.player)
    others = @league.event_participants.where.not(id: participant.id).order(:created_at).first(3)
    LeagueBuilder.fill_table!(@league, [participant, *others])

    delete league_registration_path(@league)

    assert_equal I18n.t("leagues.tables.not_allowed.finish_first"), flash[:alert]
    assert_not participant.reload.dropped?
  end

  private

  def sign_in
    post session_path, params: { session: { email_address: @user.email_address, password: "password123" } }
  end
end
