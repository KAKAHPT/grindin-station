# frozen_string_literal: true

require "application_system_test_case"

# A league game from a phone: open a table, join, the winner reports, a tablemate asks for a correction and the
# organizer answers it.
class LeagueOpenTablesTest < ApplicationSystemTestCase
  setup do
    @organizer = users(:organizer_user)
    @league = LeagueBuilder.build(players: 5, organizer: @organizer.event_organizer)
    @players = @league.event_participants.order(:created_at).to_a
    @users =
      @players.first(2).map do |participant|
        user = User.create!(name: participant.name, email_address: "liga-sys-#{SecureRandom.hex(4)}@example.com",
                            password: "password123", confirmed_at: Time.current)
        participant.update!(player: user.player)
        user
      end
  end

  test "open, join, report, ask for a correction and the organizer corrects it" do # rubocop:disable Metrics/BlockLength
    phone(0) do
      visit league_path(@league, tab: "tables")
      click_button I18n.t("leagues.tables.open")
      assert_selector "[data-my-table=waiting] li", count: 1
      assert_fits_the_phone
    end
    table = @league.league_tables.sole

    phone(1) do
      visit league_path(@league, tab: "tables")
      assert_selector "[data-waiting-table] li", count: 1
      assert_fits_the_phone
      click_button I18n.t("leagues.tables.join")
      assert_selector "[data-my-table=waiting] li", count: 2
    end
    @players[2..3].each { |participant| Leagues::Tables::Join.call(table: table, participant: participant) }

    phone(0) do
      visit league_path(@league, tab: "mine")
      assert_selector "[data-my-table=filled] li[data-seat]", count: 4
      assert_fits_the_phone
      click_button I18n.t("leagues.tables.i_won")
      assert_text I18n.t("leagues.tables.notices.reported")
      assert_selector "[data-league-played] li[data-winner]", text: @players[0].name

      click_link I18n.t("leagues.tabs.standings")
      assert_selector "[data-league-row='#{@players[0].id}'] [data-league-win-rate]", text: "100%"
      assert_selector "[data-league-me]", text: "1"
      assert_fits_the_phone
    end
    assert_predicate table.reload.pod, :finished?

    phone(1) do
      visit league_path(@league, tab: "played")
      assert_selector "[data-league-table] li[data-winner]", text: @players[0].name
      assert_fits_the_phone
      find("[data-correction-open]").click
      find("dialog[open] textarea").fill_in with: "It was a draw"
      click_button I18n.t("leagues.tables.correction_send")
      assert_text I18n.t("leagues.tables.notices.correction_requested")
      assert_selector "[data-correction=pending]"
    end

    sign_in_as(@organizer)
    visit organizer_league_path(@league)
    within "[data-correction-request]" do
      assert_text "It was a draw"
      select I18n.t("league_desk.draw"), from: "result"
      click_button I18n.t("league_desk.correct")
    end
    assert_text I18n.t("league_desk.n_correction_corrected")
    assert_equal "corrected", table.reload.correction_state
    assert(table.pod.results.merge(Result.current).all?(Draw))
  end

  private

  def phone(index)
    Capybara.using_session("league-player-#{index}") do
      unless (@signed_in ||= {})[index]
        use_phone_viewport
        sign_in_as(@users[index])
        @signed_in[index] = true
      end
      yield
    end
  end

  # Nothing pushes the page wider than the phone's screen.
  def assert_fits_the_phone
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
  end
end
