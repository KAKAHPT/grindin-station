# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class AdminSummaryControllerTest < ActionDispatch::IntegrationTest
      TOKEN = "t" * 40
      PATH = "/api/v1/admin/summary"

      def with_token(value)
        previous = ENV.fetch("JARVIS_API_TOKEN", nil)
        ENV["JARVIS_API_TOKEN"] = value
        yield
      ensure
        ENV["JARVIS_API_TOKEN"] = previous
      end

      def get_summary(token = TOKEN)
        headers = token ? { "Authorization" => "Bearer #{token}" } : {}
        get PATH, headers: headers
      end

      test "answers 404 to everyone while the token is unset, blank or too short" do
        [nil, "", "   ", "s" * 31].each do |value|
          with_token(value) do
            get_summary(value.presence || TOKEN)
            assert_response :not_found, value.inspect
          end
        end
      end

      test "answers 401 to a missing or wrong token" do
        with_token(TOKEN) do
          get_summary(nil)
          assert_response :unauthorized
          get_summary("x" * 40)
          assert_response :unauthorized
          get PATH, headers: { "Authorization" => TOKEN }
          assert_response :unauthorized
        end
      end

      test "the right token gets the summary, never cached, without a session cookie" do
        with_token(TOKEN) { get_summary }

        assert_response :success
        assert_equal "application/json", response.media_type
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_nil response.headers["Set-Cookie"]
        body = response.parsed_body
        assert_equal %w[accounts generated_at requests totals tournaments weekly], body.keys.sort
        assert Time.iso8601(body["generated_at"])
      end

      test "totals count people, events, running tournaments, error groups and pending requests" do
        tournament = events(:medium_tournament)
        tournament.update_columns(state: Tournament.states[:swiss]) # rubocop:disable Rails/SkipsModelValidations
        2.times { ErrorEvent.create!(fingerprint: "same", error_class: "RuntimeError", source: "job") }
        ErrorEvent.create!(fingerprint: "done", error_class: "RuntimeError", source: "job", resolved_at: Time.current)
        WaitlistSignup.create!(name: "Ana", email: "ana@example.com")
        WaitlistSignup.create!(name: "Rui", email: "rui@example.com", approved_at: Time.current)

        with_token(TOKEN) { get_summary }
        totals = response.parsed_body["totals"]

        assert_equal({ "players" => Player.count, "users" => User.where(anonymized_at: nil).count,
                       "organizers" => EventOrganizer.count, "tournaments" => Tournament.count,
                       "tournaments_running" => Tournament.ongoing.count, "errors_unresolved" => 1,
                       "requests_pending" => 1 }, totals)
        assert_operator totals["tournaments_running"], :>=, 1
      end

      test "weekly has the last 12 weeks, oldest first, with accounts and requests" do
        WaitlistSignup.create!(name: "Ana", email: "ana@example.com")
        with_token(TOKEN) { get_summary }
        weekly = response.parsed_body["weekly"]

        assert_equal 12, weekly.size
        starts = weekly.map { |week| Date.iso8601(week["week_start"]) }
        assert_equal starts.sort, starts
        assert_equal Time.current.beginning_of_week.to_date, starts.last
        assert_equal(User.where(created_at: starts.first.beginning_of_day..).count, weekly.sum { |w| w["accounts"] })
        assert_equal 1, weekly.last["requests"]
      end

      test "requests carry their status and whether an account has that e-mail" do
        pending = WaitlistSignup.create!(name: "Ana", email: users(:player_one).email_address)
        WaitlistSignup.create!(name: "Rui", email: "rui@example.com", approved_at: Time.current)
        WaitlistSignup.create!(name: "Eva", email: "eva@example.com", declined_at: Time.current)

        with_token(TOKEN) { get_summary }
        rows = response.parsed_body["requests"].index_by { |row| row["name"] }

        assert_equal %w[pending approved declined], rows.values_at("Ana", "Rui", "Eva").pluck("status")
        assert_equal [true, false, false], rows.values_at("Ana", "Rui", "Eva").pluck("has_account")
        assert_equal pending.id, rows["Ana"]["id"]
        assert_equal pending.email, rows["Ana"]["email"]
        assert Time.iso8601(rows["Ana"]["created_at"])
      end

      test "accounts never carry an e-mail and skip removed accounts" do
        removed = users(:player_two)
        Accounts::Anonymize.call(user: removed)

        with_token(TOKEN) { get_summary }
        accounts = response.parsed_body["accounts"]

        assert_equal %w[created_at handle id name], accounts.first.keys.sort
        assert_no_match(/@/, accounts.to_json)
        assert_not_includes accounts.pluck("id"), removed.id
        assert_includes accounts.pluck("handle"), users(:player_one).handle
      end

      test "tournaments list the newest first with their players and organizer" do
        with_token(TOKEN) { get_summary }
        rows = response.parsed_body["tournaments"]
        row = rows.find { |r| r["slug"] == "small-tournament" }

        assert_equal Tournament.order(created_at: :desc).limit(50).pluck(:slug), rows.pluck("slug")
        assert_equal({ "slug" => "small-tournament", "name" => "Small Tournament", "state" => "draft",
                       "format" => "multiplayer", "players" => 4, "organizer" => "Tournament Organizer" },
                     row.except("start_time"))
        assert Time.iso8601(row["start_time"])
      end
    end
  end
end
