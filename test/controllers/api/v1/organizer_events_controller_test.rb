# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class OrganizerEventsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @organizer = event_organizers(:standard_organizer)
        @handle = @organizer.user.handle
      end

      def get_events(handle = @handle)
        get "/api/v1/organizers/#{handle}/events"
        response.parsed_body
      end

      def slugs = get_events.fetch("events").pluck("slug")

      test "lists the organizer's open and running events, soonest first, as public cached JSON" do
        later = TournamentBuilder.build(players: 3, organizer: @organizer, state: :registration_open)
        later.update_columns(start_time: 10.days.from_now, end_time: 11.days.from_now) # rubocop:disable Rails/SkipsModelValidations
        running = TournamentBuilder.build(players: 4, organizer: @organizer, state: :swiss)

        body = get_events

        assert_response :success
        assert_equal "application/json", response.media_type
        assert_equal %w[max-age=30 public], response.headers["Cache-Control"].split(", ").sort
        assert_nil response.headers["Set-Cookie"]
        assert_equal @handle, body.dig("organizer", "handle")
        listed = body["events"].pluck("slug")
        assert_operator listed.index(running.slug), :<, listed.index(later.slug)

        event = body["events"].find { |e| e["slug"] == later.slug }
        assert_equal "tournament", event["kind"]
        assert_equal "http://www.example.com/t/#{later.slug}", event["url"]
        assert_equal 3, event["players"]
        assert_equal later.start_time.utc.iso8601, event["starts_at"]
        assert_equal false, event["dateTba"]
        assert event["cover"].start_with?("http://www.example.com/")
      end

      test "leaves out drafts, canceled, finished and past events" do
        hidden = %i[draft canceled finished].map do |state|
          TournamentBuilder.build(players: 0, organizer: @organizer, state: state)
        end
        past = TournamentBuilder.build(players: 0, organizer: @organizer, state: :registration_open)
        past.update_columns(start_time: 3.days.ago, end_time: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations

        assert_empty slugs & (hidden + [past]).map(&:slug)
      end

      test "a date to be announced has no dates" do
        tba = TournamentBuilder.build(players: 0, organizer: @organizer, state: :registration_open)
        tba.update_columns(date_tba: true) # rubocop:disable Rails/SkipsModelValidations

        event = get_events["events"].find { |e| e["slug"] == tba.slug }
        assert event["dateTba"]
        assert_nil event["starts_at"]
        assert_nil event["ends_at"]
      end

      test "lists leagues too, linked to their league page" do
        league = LeagueBuilder.build(players: 2, organizer: @organizer, state: :registration_open)

        event = get_events["events"].find { |e| e["slug"] == league.slug }
        assert_equal "league", event["kind"]
        assert_equal "http://www.example.com/leagues/#{league.to_param}", event["url"]
      end

      test "an unknown or suspended organizer is not found" do
        get_events("nobody-here")
        assert_response :not_found

        @organizer.update!(suspended_at: Time.current)
        get_events
        assert_response :not_found
      end
    end
  end
end
