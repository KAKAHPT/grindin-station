# frozen_string_literal: true

require "test_helper"

class ErrorRecorderTest < ActiveSupport::TestCase
  setup do
    @recorder = ErrorRecorder.new
    Rails.error.subscribe(@recorder)
  end

  teardown do
    Rails.error.unsubscribe(@recorder)
    Current.reset
  end

  def boom(message)
    raise message
  rescue RuntimeError => e
    e
  end

  # Raised inside app/ (SeatSimulator's mode check) with a different message each time.
  def app_error(mode)
    Tournaments::SeatSimulator.new(players: 8, rounds: 1, rng: Random.new(1), mode: mode)
  rescue ArgumentError => e
    e
  end

  test "two errors from the same app line share one fingerprint" do
    assert_difference -> { ErrorEvent.count }, 2 do
      Rails.error.report(app_error(:first), handled: false)
      Rails.error.report(app_error(:second), handled: false)
    end

    assert_equal 1, ErrorEvent.distinct.count(:fingerprint)
    event = ErrorEvent.find_by(message: "unknown mode :second")
    assert_equal "ArgumentError", event.error_class
    assert_equal "other", event.source
    assert_operator event.backtrace.lines.size, :<=, 30
    assert_includes event.backtrace.lines.first, "seat_simulator.rb"
  end

  test "Postgres DETAIL lines are not stored" do
    Rails.error.report(boom("PG::UniqueViolation: duplicate key\nDETAIL: Key (email_address)=(x@y.z) already exists."),
                       handled: true)

    assert_equal "PG::UniqueViolation: duplicate key", ErrorEvent.last.message
  end

  test "source, user, path and request id come from the context" do
    user = users(:player_one)
    Current.request_id = "req-1"
    Current.request_path = "/somewhere"
    Rails.error.report(boom("job"), handled: true, source: "job", context: { user_id: user.id })

    event = ErrorEvent.last
    assert_equal "job", event.source
    assert_equal user.id, event.user_id
    assert_equal "/somewhere", event.path
    assert_equal "req-1", event.request_id
  end

  test "a job or controller in the context sets the source" do
    Rails.error.report(boom("a"), handled: false, context: { job: Object.new })
    Rails.error.report(boom("b"), handled: false, context: { controller: Object.new, path: "/x" })

    assert_equal %w[job request], ErrorEvent.order(:message).pluck(:source)
    assert_equal "/x", ErrorEvent.find_by(message: "b").path
  end

  test "long messages are truncated" do
    Rails.error.report(boom("m" * 5000), handled: false)

    assert_equal "m" * 4000, ErrorEvent.last.message
  end

  test "its own failures are swallowed" do
    ErrorEvent.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "down" }
    assert_nothing_raised { Rails.error.report(boom("x"), handled: false) }
  ensure
    ErrorEvent.singleton_class.remove_method(:create!)
  end
end
