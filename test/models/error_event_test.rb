# frozen_string_literal: true

require "test_helper"

class ErrorEventTest < ActiveSupport::TestCase
  def raised(klass = RuntimeError, message = "boom", backtrace: caller)
    error = klass.new(message)
    error.set_backtrace(backtrace)
    error
  end

  test "the fingerprint is the class and the first app frame" do
    frames = ["/gems/x.rb:1", "/srv/app/models/a.rb:3:in 'x'", "/srv/app/models/b.rb:9"]
    expected = Digest::SHA256.hexdigest("RuntimeError|/srv/app/models/a.rb:3:in 'x'")

    assert_equal expected, ErrorEvent.fingerprint_for(raised(backtrace: frames))
    assert_equal expected, ErrorEvent.fingerprint_for(raised(RuntimeError, "other message", backtrace: frames))
    assert_not_equal expected, ErrorEvent.fingerprint_for(raised(ArgumentError, backtrace: frames))
  end

  test "without an app frame the message stands in" do
    assert_equal Digest::SHA256.hexdigest("RuntimeError|boom"),
                 ErrorEvent.fingerprint_for(raised(backtrace: ["/gems/x.rb:1"]))
    assert_equal Digest::SHA256.hexdigest("RuntimeError|boom"), ErrorEvent.fingerprint_for(RuntimeError.new("boom"))
  end

  test "unresolved and grouped" do
    2.times { ErrorEvent.create!(fingerprint: "a", error_class: "RuntimeError", message: "m", source: "other") }
    ErrorEvent.create!(fingerprint: "b", error_class: "RuntimeError", message: "m", source: "other",
                       resolved_at: Time.current)

    assert_equal %w[a a], ErrorEvent.unresolved.pluck(:fingerprint)
    group = ErrorEvent.unresolved.grouped.to_a
    assert_equal 1, group.size
    assert_equal "a", group.first.fingerprint
    assert_equal 2, group.first.occurrences
    assert_not_nil group.first.last_seen_at
  end
end
