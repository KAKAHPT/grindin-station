# frozen_string_literal: true

require "test_helper"

module Admin
  class InvitationalControllerTest < ActionDispatch::IntegrationTest
    setup do
      @organizer = event_organizers(:standard_organizer)
      @year = Date.current.year
      @gold = finished_event(winners: { 1 => 0 }, tier: "gold")
      @gold_draw = finished_event(winners: { 1 => :draw }, tier: "gold")
      @plain = finished_event(winners: { 1 => 0 }, tier: "none")
      @old = finished_event(winners: { 1 => 0 }, tier: "platinum", year: @year - 1)
      Rankings::Rebuild.call
      sign_in users(:admin_user)
    end

    test "invitational points are the ranking points times the tier multiplier" do
      gold = RankingContribution.where(event: [@gold, @gold_draw])
      assert(gold.any? { |row| row.points.positive? })
      gold.each { |row| assert_equal row.points * 2, row.invitational_points }
      assert_equal [BigDecimal("0")], RankingContribution.where(event: @plain).distinct.pluck(:invitational_points)
    end

    test "lists the current season's players with invitational points, highest first" do
      get admin_invitational_path

      assert_response :success
      expected =
        RankingContribution.where(season: @year).where("invitational_points > 0")
          .group(:player_id).sum(:invitational_points).sort_by { |_, sum| -sum }
      assert_equal expected.map(&:first), listed_ids
      sums = css_select("tr[data-player] [data-invitational]").map { |node| node.text.strip }
      assert_equal(expected.map { |_, sum| ApplicationController.helpers.ranking_points(sum) }, sums)
      assert_not_includes listed_ids, winner_of(@old)
      assert_select "a[href='#{admin_invitational_export_path(season: @year)}']"
      assert_select ".seg a.seg-on", text: @year.to_s
    end

    test "the season control picks a past year or all of them" do
      get admin_invitational_path(season: @year - 1)

      assert_equal [winner_of(@old)], listed_ids

      get admin_invitational_path(season: "all")

      ids = listed_ids
      assert_includes ids, winner_of(@old)
      assert_includes ids, winner_of(@gold)
      assert_select "a[href='#{admin_invitational_export_path(season: 'all')}']"
    end

    test "the CSV export downloads the season and audits it" do
      get admin_invitational_export_path(season: @year)

      assert_response :success
      assert_equal "text/csv", response.media_type
      rows = CSV.parse(response.body.delete_prefix(Exports::CsvFile::BOM), row_sep: "\r\n")
      assert_equal %w[standing name handle email invitational_points tier_events points events], rows.first
      assert_operator rows.size, :>, 1
      audit = AuditEvent.recent.first
      assert_equal ["data_exported", users(:admin_user), { "kind" => "invitational", "season" => @year.to_s }],
                   [audit.action, audit.actor_user, audit.data]
    end

    test "a non-admin gets a 404 on the page and the export" do
      delete session_path
      sign_in users(:organizer_user)

      get admin_invitational_path
      assert_response :not_found

      get admin_invitational_export_path
      assert_response :not_found
    end

    test "the public rankings and event pages say nothing about tiers" do
      delete session_path

      [rankings_path(season: "all"), play_event_path(@gold.slug)].each do |path|
        get path

        assert_response :success
        assert_no_match(/\b(tier|tiers|gold|platinum|invitational)\b/i, response.body.gsub(/<[^>]*>/, " "), path)
      end
    end

    private

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end

    def listed_ids = css_select("tr[data-player]").pluck("data-player")

    def winner_of(event)
      RankingContribution.where(event: event).order(points: :desc).first.player_id
    end

    def finished_event(winners:, tier:, year: @year)
      event = TournamentBuilder.build(players: 4, organizer: @organizer, state: :swiss)
      start = Time.zone.local(year, 6, 1)
      event.update_columns(swiss_rounds_count: 1, top_cut_size: 0, start_time: start, end_time: start + 1.day, # rubocop:disable Rails/SkipsModelValidations
                           tier: tier)
      event.rounds.create!(type: SwissRound, number: 1)
      TournamentBuilder.play_round!(event, winners: winners)
      event.update_column(:state, Tournament.states[:finished]) # rubocop:disable Rails/SkipsModelValidations
      event.reload
    end
  end
end
