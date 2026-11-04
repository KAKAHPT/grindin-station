# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class EventsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
      include FeedTournament

      setup { build_feed_tournament }

      FEEDS = %i[standings rounds info].freeze

      def with_memory_rate_limit_store
        store = BaseController.cache_store
        memory = ActiveSupport::Cache::MemoryStore.new
        store.define_singleton_method(:increment) { |*args, **options| memory.increment(*args, **options) }
        yield
      ensure
        store.singleton_class.remove_method(:increment)
      end

      test "the three feeds answer JSON with public 30 s caching and open CORS, without a session cookie" do
        FEEDS.each do |feed|
          get "/api/v1/events/#{@t.slug}/#{feed}", headers: { "Origin" => "https://obs.example" }

          assert_response :success
          assert_equal "application/json", response.media_type
          assert_equal "*", response.headers["Access-Control-Allow-Origin"], feed
          assert_equal %w[max-age=30 public], response.headers["Cache-Control"].split(", ").sort, feed
          assert response.headers["ETag"].present?, feed
          assert_nil response.headers["Set-Cookie"], feed
          assert_equal @t.slug, response.parsed_body["tid"]
        end
      end

      test "CORS stays off outside the API" do
        get "/t/#{@t.slug}/standings", headers: { "Origin" => "https://obs.example" }
        assert_nil response.headers["Access-Control-Allow-Origin"]
      end

      test "standings come in rank order with seats and an empty commander by default" do
        @t.event_participants.update_all(decklist: "Kinnan, Bonder Prodigy") # rubocop:disable Rails/SkipsModelValidations
        get "/api/v1/events/#{@t.slug}/standings"
        rows = response.parsed_body["standings"]

        assert_equal (1..16).to_a, rows.pluck("rank")
        assert_equal [""] * 16, rows.pluck("commander")
        assert_equal %w[1 2 3 4], rows.first["seats"].keys
        assert_equal 2, rows.first["seats"].values.sum
      end

      test "commanders show when the event allows it, links never do, and slashes stay unescaped" do
        @t.update_columns(show_commanders_in_standings: true) # rubocop:disable Rails/SkipsModelValidations
        first, second = seated(@round1, 1)
        first.update_columns(decklist: "Tymna / Thrasios") # rubocop:disable Rails/SkipsModelValidations
        second.update_columns(decklist: "https://moxfield.com/decks/abc") # rubocop:disable Rails/SkipsModelValidations
        seated(@round1, 2).first.update_columns(decklist: "www.archidekt.com/decks/1") # rubocop:disable Rails/SkipsModelValidations

        %i[standings rounds].each do |feed|
          get "/api/v1/events/#{@t.slug}/#{feed}"
          assert_includes response.body, "Tymna / Thrasios"
          assert_no_match %r{https?://|www\.|moxfield|archidekt}, response.body
        end
      end

      test "rounds ignore an unpublished round and seat every player once per round" do
        TournamentBuilder.play_round!(@t, winners: { 2 => 0, 3 => 0, 4 => 0 }) # pod 1 is reported
        @t.rounds.create!(type: SwissRound, number: 3) # not published
        get "/api/v1/events/#{@t.slug}/rounds"
        body = response.parsed_body

        assert_equal %w[1 2], body["rounds"].pluck("round")
        assert_equal "2", body["latest"]
        body["rounds"].each do |round|
          names = round["tables"].flat_map { |table| table["players"].pluck("name") }
          assert_equal 16, names.size
          assert_equal names.uniq, names
          assert(round["tables"].all? { |table| table["players"].any? })
        end
      end

      test "byes are not tables" do
        user = User.create!(name: "Bye", email_address: "bye-#{SecureRandom.hex(3)}@example.com",
                            password: "password123")
        bye = @t.event_participants.create!(player: user.player, accepted_terms: true)
        Advance.create!(round: @round2, event_participant: bye)
        get "/api/v1/events/#{@t.slug}/rounds"

        names = response.parsed_body["rounds"].last["tables"].flat_map { |table| table["players"].pluck("name") }
        assert_not_includes names, "Bye"
        assert_equal 4, response.parsed_body["rounds"].last["tables"].size
      end

      test "info has the current round and its timer end in ISO 8601" do
        get "/api/v1/events/#{@t.slug}/info"
        body = response.parsed_body

        assert_equal "2", body["round"]
        assert_equal "2026-11-04T16:20:00Z", body["timerEnd"]
        assert_equal 16, body["players"]
      end

      test "draft, canceled and unknown events are a JSON 404" do
        %i[draft canceled].each do |state|
          @t.update_columns(state: Tournament.states[state]) # rubocop:disable Rails/SkipsModelValidations
          FEEDS.each do |feed|
            get "/api/v1/events/#{@t.slug}/#{feed}"
            assert_response :not_found
            assert_equal({ "error" => "not_found" }, response.parsed_body)
          end
        end
        get "/api/v1/events/no-such-event/standings"
        assert_response :not_found
        assert_equal({ "error" => "not_found" }, response.parsed_body)
      end

      test "a staff session does not open a draft event's feeds" do
        post session_path,
             params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
        @t.update_columns(state: Tournament.states[:draft]) # rubocop:disable Rails/SkipsModelValidations
        get "/api/v1/events/#{@t.slug}/standings"
        assert_response :not_found
      end

      test "a repeated request with the ETag is a 304 until something changes" do
        get "/api/v1/events/#{@t.slug}/rounds"
        etag = response.headers["ETag"]

        get "/api/v1/events/#{@t.slug}/rounds", headers: { "If-None-Match" => etag }
        assert_response :not_modified

        travel 1.minute do
          Draw.create!(round: @round2, event_participant: seated(@round2, 3).first)
          get "/api/v1/events/#{@t.slug}/rounds", headers: { "If-None-Match" => etag }
          assert_response :success
          assert_not_equal etag, response.headers["ETag"]
        end
      end

      test "renaming a player changes the ETag" do
        get "/api/v1/events/#{@t.slug}/standings"
        etag = response.headers["ETag"]

        travel 1.minute do
          seated(@round1, 1).first.player.user.update!(name: "Novo Nome")
          get "/api/v1/events/#{@t.slug}/standings", headers: { "If-None-Match" => etag }
          assert_response :success
          assert_includes response.parsed_body["standings"].pluck("name"), "Novo Nome"
        end
      end

      # The test environment caches nothing (null store); the limiter's store is swapped for a memory
      # store just for this test.
      test "the 121st request from one address within a minute is a JSON 429" do
        with_memory_rate_limit_store do
          120.times do
            get "/api/v1/events/#{@t.slug}/info"
            assert_response :success
          end
          get "/api/v1/events/#{@t.slug}/standings"
          assert_response :too_many_requests
          assert_equal({ "error" => "rate_limited" }, response.parsed_body)

          travel 61.seconds do
            get "/api/v1/events/#{@t.slug}/info"
            assert_response :success
          end
        end
      end

      test "two events never share a body or an ETag" do
        other = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer))
        FEEDS.each do |feed|
          get "/api/v1/events/#{@t.slug}/#{feed}"
          first_body = response.body
          first_etag = response.headers["ETag"]

          get "/api/v1/events/#{other.slug}/#{feed}", headers: { "If-None-Match" => first_etag }
          assert_response :success
          assert_equal other.slug, response.parsed_body["tid"]
          assert_not_equal first_body, response.body
          assert_not_equal first_etag, response.headers["ETag"]
        end
      end

      test "the feeds share no ETag with each other" do
        etags =
          FEEDS.map do |feed|
            get "/api/v1/events/#{@t.slug}/#{feed}"
            response.headers["ETag"]
          end
        assert_equal etags.uniq, etags
      end
    end
  end
end
