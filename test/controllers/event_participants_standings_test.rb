# frozen_string_literal: true

require "test_helper"

class EventParticipantsStandingsTest < ActionDispatch::IntegrationTest
  setup do
    @tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
    @tournament.update_columns(seed: 99, swiss_rounds_count: 2, top_cut_size: 0) # rubocop:disable Rails/SkipsModelValidations
    @tournament.rounds.create!(type: SwissRound, number: 1)
    TournamentBuilder.play_round!(@tournament, winners: { 1 => 0, 2 => :draw })
    @tournament.update_columns(show_beaten_in_standings: true, show_unique_in_standings: true) # rubocop:disable Rails/SkipsModelValidations
  end

  test "public standings show the tiebreaker columns and explain them" do
    get play_standings_path(@tournament.slug)

    assert_response :success
    assert_standings_headers(:en)
    assert_select "p", text: I18n.t("standings.help.beaten")
  end

  test "public standings render in portuguese" do
    get play_standings_path(@tournament.slug, locale: "pt")

    assert_response :success
    assert_standings_headers(:pt)
    assert_select "th", text: /\A\s*Batidos\s*\z/
    assert_select "p", text: I18n.t("standings.help.beaten", locale: :pt)
  end

  test "the portuguese standings have no english headers or tooltips" do
    get play_standings_path(@tournament.slug, locale: "pt")

    %w[Rank Player W-L-D].each { |header| assert_select "th", text: /\A\s*#{header}\s*\z/, count: 0 }
    assert_select "th", text: /\A\s*Jogador\s*\z/
    assert_no_match(/Player rank is calculated|Wins - Losses - Draws/, response.body)
  end

  test "the public list before the swiss hides waitlisted players and player keys" do
    tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                         state: :registration_open)
    waiting = tournament.event_participants.create!(player_name: "Espera Dois", accepted_terms: true,
                                                    player_email: "espera-#{SecureRandom.hex(3)}@example.com")
    waiting.update_columns(waitlisted: true, waitlist_position: 1) # rubocop:disable Rails/SkipsModelValidations

    get play_standings_path(tournament.slug)

    assert_response :success
    assert_select "tbody tr", 4
    assert_no_match(/Espera Dois/, response.body)
    tournament.event_participants.where(waitlisted: false).includes(:player).find_each do |participant|
      assert_not_includes response.body, "##{participant.player.key[0, 5]}"
      assert_select "#tooltip-#{participant.id}", text: /\A\s*#{Regexp.escape(participant.name)}\s*\z/
    end
  end

  test "public standings render before any round is published" do
    tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
    tournament.rounds.create!(type: SwissRound, number: 1)

    get play_standings_path(tournament.slug)

    assert_response :success
  end

  test "waitlisted players are not ranked in the standings" do
    waiting = @tournament.event_participants.create!(player_name: "Espera Um", accepted_terms: true,
                                                     player_email: "espera-#{SecureRandom.hex(3)}@example.com")
    waiting.update_columns(waitlisted: true, waitlist_position: 1) # rubocop:disable Rails/SkipsModelValidations

    get play_standings_path(@tournament.slug)

    assert_response :success
    assert_select "tbody tr", 8
    assert_select "tbody", text: /Espera Um/, count: 0
  end

  private

  def assert_standings_headers(locale)
    %i[points owr beaten unique].each do |column|
      header = I18n.t("standings.columns.#{column}", locale: locale)
      assert_select "th", text: /\A\s*#{Regexp.escape(header)}\s*\z/
    end
    # Seat history is on the player's own table, not in the public standings.
    assert_select "th", text: I18n.t("standings.columns.seats", locale: locale), count: 0
    assert_select "tbody span[role=img]", count: 0
  end
end
