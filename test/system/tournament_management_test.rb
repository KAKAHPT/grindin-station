# frozen_string_literal: true

require "application_system_test_case"

class TournamentManagementTest < ApplicationSystemTestCase # rubocop:disable Metrics/ClassLength
  test "organizer can create tournament with all fields" do
    organizer = users(:organizer_user)
    sign_in_as(organizer)

    visit organizer_tournaments_path
    click_link "New tournament"

    fill_in "Name", with: "Grand Championship 2024"
    fill_in "Description", with: "The biggest tournament of the year"
    fill_in "Maximum participants", with: "32"
    fill_in "Address", with: "Lisboa, Portugal"
    fill_in "Start time", with: Time.zone.now.tomorrow.change(sec: 0)
    fill_in "End time", with: Time.zone.now.tomorrow.change(sec: 0)

    click_button "Create Tournament"
    assert_text I18n.t("flash.notice.tournament_created")

    # Verify tournament was created
    tournament = Tournament.find_by(name: "Grand Championship 2024")
    assert_not_nil tournament
    assert_equal "registration_open", tournament.state
  end

  test "the form follows the format: 1v1 points, match length and cut sizes; typed points survive" do
    sign_in_as(users(:organizer_user))
    visit new_organizer_tournament_path

    assert_no_selector "#tournament_match_games"
    select "Legacy", from: "Format"

    assert_equal(%w[3 1 0 3],
                 %w[win draw loss bye].map { |kind| find_field("tournament[points_#{kind}]").value })
    assert_selector "#tournament_match_games", visible: true
    cut_sizes = find_by_id("tournament_top_cut_size").all("option").map(&:text)
    assert_includes cut_sizes, "Top 8"
    assert_not_includes cut_sizes, "Top 10"

    fill_in "tournament[points_win]", with: "5"
    select "Commander / cEDH", from: "Format"
    assert_no_selector "#tournament_match_games"
    assert_includes find_by_id("tournament_top_cut_size").all("option").map(&:text), "Top 10"
    select "Legacy", from: "Format"

    assert_field "tournament[points_win]", with: "5"
    assert_field "tournament[points_bye]", with: "3"
  end

  test "typed points kept by a failed create are not reset by a format switch" do
    sign_in_as(users(:organizer_user))
    visit new_organizer_tournament_path

    fill_in "Name", with: "Duelos"
    fill_in "Start time", with: Time.zone.now.tomorrow.change(sec: 0)
    fill_in "End time", with: Time.zone.now.tomorrow.change(sec: 0)
    select "Legacy", from: "Format"
    fill_in "tournament[points_win]", with: "5"
    fill_in "tournament[round_minutes]", with: "0"
    execute_script("document.getElementById('tournament_round_minutes').closest('form').noValidate = true")
    click_button "Create Tournament"

    # The re-rendered page (a fresh format-fields connect()), not the page that was submitted.
    assert_text "must be greater than or equal to 1"
    assert_field "tournament[points_win]", with: "5"
    select "Commander / cEDH", from: "Format"
    assert_field "tournament[points_win]", with: "5"
    assert_field "tournament[points_bye]", with: "3"
  end

  test "organizer can edit tournament details" do
    organizer = users(:organizer_user)
    tournament = events(:small_tournament)
    sign_in_as(organizer)

    visit organizer_tournament_path(tournament)
    click_link "Settings"

    fill_in "Name", with: "Updated Tournament Name"
    fill_in "Description", with: "Updated description"

    click_button "Update"
    assert_text I18n.t("flash.notice.tournament_updated")

    tournament.reload
    assert_equal "Updated Tournament Name", tournament.name
  end

  test "organizer can manage tournament participants" do
    organizer = users(:organizer_user)
    tournament = events(:medium_tournament_registration_open)
    sign_in_as(organizer)

    visit organizer_tournament_path(tournament)
    click_link "Roster"

    assert_selector "[data-tabs] .tab-on", text: "Roster"

    # Add participant manually via modal form
    click_link "Add player"

    fill_in "Player email", with: "tiago@king.com"
    fill_in "Player name", with: "Tiago Rei"
    fill_in "Decklist", with: "https://moxfield.com/rog-si"
    check "Player has read and accepted event rules"
    click_button "Create Event participant"

    # Verify redirect happened - notice appears and participant is shown
    assert_text "added!"
    assert_text "Tiago Rei"
  end

  test "organizer can submit penalties and infractions" do
    organizer = users(:organizer_user)
    tournament = events(:small_tournament)
    participant = tournament.event_participants.first
    sign_in_as(organizer)

    # Navigate to infraction creation page
    visit new_organizer_tournament_infraction_path(tournament, player_id: participant.player_id)

    # Select matching kind, category, and penalty
    select "Unsporting Conduct", from: "Kind"
    select "Minor", from: "Category"
    select "Warning", from: "Penalty"
    fill_in "Description", with: "Player was rude to opponent"

    click_button "Record Infraction"

    assert_text "Infraction added successfully"
    assert Infraction.exists?(
      player: participant.player,
      kind: "unsporting_conduct"
    )
  end

  test "organizer can view comprehensive tournament reports" do
    organizer = users(:organizer_user)
    tournament = events(:finished_tournament)
    sign_in_as(organizer)

    visit organizer_tournament_path(tournament)

    assert_text tournament.name
    assert_text "Finished"

    # View standings via Participants
    click_link "Roster"

    assert_selector "[data-tabs] .tab-on", text: "Roster"
    tournament.event_participants.each do |participant|
      assert_text participant.player.user.name
    end

    # View round details
    tournament.rounds.each_with_index do |round, index|
      visit organizer_tournament_path(tournament)
      click_link "Rounds"

      assert_text "Round #{index + 1}"
      round.pods.each do |pod|
        pod.event_participants.each do |participant|
          assert_text participant.player.user.name
        end
      end
    end
  end
end
