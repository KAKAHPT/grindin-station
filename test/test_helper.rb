# frozen_string_literal: true

require "simplecov"

SimpleCov.start "rails" do
  # Use a unique name for each parallel worker
  command_name "Job #{ENV['TEST_ENV_NUMBER']}" if ENV["TEST_ENV_NUMBER"]

  # Optional: filter out specific directories
  skip "/bin/"
  skip "/db/"
  skip "/test/"
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "support/tournament_builder"
require_relative "support/feed_tournament"
require_relative "support/rate_limit_store"

# Allow WebMock to work with Selenium for system tests
WebMock.disable_net_connect!(allow_localhost: true)

# Sign in with Google / Discord never leaves the process in tests.
OmniAuth.config.test_mode = true

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # SimpleCov Parallel Setup
    parallelize_setup do |worker|
      SimpleCov.command_name "#{SimpleCov.command_name}-worker-#{worker}"
    end

    parallelize_teardown do |_worker|
      SimpleCov.result
    end

    # Setup all fixtures in test/fixtures/*.yml
    fixtures :all

    setup do
      # NOTE: Ensure Event is loaded; sometimes resetting counters
      # on a model here can trigger early loading.
      Event.reset_counters if defined?(Event)
    end

    teardown do
      OmniAuth.config.mock_auth.except!(:google_oauth2, :discord)
    end
  end
end
