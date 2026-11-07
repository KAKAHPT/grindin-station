# frozen_string_literal: true

require "test_helper"
require_relative "../../support/export_tournament"

module Organizer
  class ExportsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    include ExportTournament

    KINDS = %w[players melee standings rounds pairings].freeze

    setup do
      @tournament = build_export_tournament
      @users = { "organizer" => users(:organizer_user) }
      %w[judge scorekeeper].each do |role|
        user = User.create!(name: role.capitalize, email_address: "#{role}-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
        EventStaff.create!(event: @tournament, user: user, role: role)
        @users[role] = user
      end
    end

    test "the organizer and the scorekeeper download every file as a CSV attachment" do
      %w[organizer scorekeeper].each do |role|
        sign_in_as(@users.fetch(role))
        KINDS.each do |kind|
          get export_path(kind)

          assert_response :success, "#{role} #{kind}"
          assert_equal "text/csv; charset=utf-8", response.headers["Content-Type"]
          file = "#{@tournament.slug}-#{kind}.csv"
          assert_equal %(attachment; filename="#{file}"; filename*=UTF-8''#{file}),
                       response.headers["Content-Disposition"]
          assert response.body.start_with?(BOM), kind
        end
      end
    end

    test "casters and users with no role on the event are refused" do
      caster = User.create!(name: "Caster", email_address: "caster-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
      EventStaff.create!(event: @tournament, user: caster, role: "caster")
      [caster, users(:player_one)].each do |user|
        sign_in_as(user)
        (KINDS + ["sheet"]).each do |kind|
          get export_path(kind)

          assert_response :redirect, "#{user.name} #{kind}"
        end
      end
      assert_equal 0, AuditEvent.where(action: "data_exported").count
    end

    test "every download writes a data_exported audit row with the kind" do
      sign_in_as(@users.fetch("scorekeeper"))

      assert_difference -> { AuditEvent.where(action: "data_exported").count }, 1 do
        get export_path("melee")
      end
      audit = AuditEvent.where(action: "data_exported").last
      assert_equal @tournament.id, audit.event_id
      assert_equal @users.fetch("scorekeeper"), audit.actor_user
      assert_equal({ "kind" => "melee" }, audit.data)
    end

    test "pairings default to the latest published round and take ?round=" do
      sign_in_as(@users.fetch("organizer"))

      get export_path("pairings")
      assert_equal Exports::Pairings.call(@tournament, round: @tournament.rounds.find_by!(number: 2)), response.body

      get export_path("pairings", round: 1)
      assert_equal Exports::Pairings.call(@tournament, round: @tournament.rounds.find_by!(number: 1)), response.body
    end

    test "pairings are not found without a published round, or for an unpublished one" do
      sign_in_as(@users.fetch("organizer"))
      round = @tournament.rounds.create!(type: SwissRound, number: 3)

      get export_path("pairings", round: round.number)
      assert_response :not_found

      @tournament.rounds.update_all(published: false) # rubocop:disable Rails/SkipsModelValidations
      get export_path("pairings")
      assert_response :not_found
    end

    test "the results sheet uses the print layout and lists the closed rounds only" do
      @tournament.rounds.create!(type: SwissRound, number: 3)
      sign_in_as(@users.fetch("scorekeeper"))

      get export_path("sheet")

      assert_response :success
      assert_select "body.print-page"
      assert_select "[data-sheet-header]", minimum: 3
      assert_select "[data-sheet-header]", text: /#{Regexp.escape(@tournament.name)}/
      assert_select "[data-sheet-header]", text: /Generated at/
      assert_select "[data-sheet-players] tbody tr", 16
      assert_select "[data-sheet-round]", 2
      assert_select "[data-sheet-round] [data-sheet-header]", text: /Round #1/
      assert_select "[data-sheet-round] [data-sheet-header]", text: /Round #2/
      assert_select "[data-sheet-round] [data-sheet-header]", text: /Round #3/, count: 0
      assert_select "[data-sheet-standings] tbody tr", 16
      assert_equal 1, AuditEvent.where(action: "data_exported", event: @tournament).count
    end

    test "the sheet shows seats with W/D/L for multiplayer and games and byes for 1v1" do
      sign_in_as(@users.fetch("organizer"))

      get export_path("sheet")
      winner = @tournament.rounds.find_by!(number: 1).pods.find_by!(number: 1).seatings.find_by!(order: 1)
      assert_select "[data-sheet-round='1'] [data-table='1'] tr", text: /#{winner.event_participant.name}\s*W/

      duel = build_export_1v1_tournament
      get export_sheet_organizer_tournament_path(duel)
      assert_response :success
      assert_select "[data-sheet-round='1'] [data-table='1']", text: /W 2-1/
      bye = duel.rounds.first.byes.first.event_participant
      assert_select "[data-sheet-round='1'] [data-sheet-byes]", text: /#{bye.name}/
    end

    test "the sheet loads without N+1 queries" do
      sign_in_as(@users.fetch("organizer"))
      without_n_plus_one { get export_path("sheet") }
      assert_response :success
    end

    test "leagues export players, melee, standings and rounds" do
      league = League.create!(name: "Liga #{SecureRandom.hex(3)}", start_time: Time.current, end_time: 1.month.from_now,
                              event_organizer: event_organizers(:standard_organizer))
      sign_in_as(@users.fetch("organizer"))

      %w[players melee standings rounds].each do |kind|
        get public_send("export_#{kind}_organizer_league_path", league)
        assert_response :success, kind
        assert_includes response.headers["Content-Disposition"], "#{league.slug}-#{kind}.csv"
      end
    end

    private

    def export_path(kind, **params)
      return export_sheet_organizer_tournament_path(@tournament, **params) if kind == "sheet"

      public_send("export_#{kind}_organizer_tournament_path", @tournament, **params)
    end

    def sign_in_as(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
