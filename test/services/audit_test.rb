# frozen_string_literal: true

require "test_helper"

class AuditTest < ActiveSupport::TestCase
  teardown { Current.reset }

  test "records one row with the request context, actor, event, subject and data" do
    user = users(:organizer_user)
    event = events(:standard_tournament)
    Current.ip_address = "10.0.0.7"
    Current.request_id = "req-123"

    row = Audit.record(:staff_added, actor: user, subject: user, event: event, user_id: user.id, role: "judge")

    assert_equal "staff_added", row.action
    assert_equal user, row.actor_user
    assert_equal user, row.subject
    assert_equal event.id, row.event_id
    assert_equal %w[10.0.0.7 req-123], [row.ip, row.request_id]
    assert_equal({ "user_id" => user.id, "role" => "judge" }, row.reload.data)
    assert_not_nil row.created_at
  end

  test "the actor defaults to the signed-in user, nil without a session" do
    assert_nil Audit.record(:sign_out).actor_user

    Current.session = users(:player_one).sessions.create!
    assert_equal users(:player_one), Audit.record(:sign_out).actor_user
  end

  test "a failing insert is logged and returns nil, never raises" do
    logged = []
    AuditEvent.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "db down" }
    Rails.logger.define_singleton_method(:error) { |message = nil| logged << message }

    assert_nil Audit.record(:sign_in)
    assert_match(/sign_in.*db down/, logged.sole)
  ensure
    AuditEvent.singleton_class.remove_method(:create!)
    Rails.logger.singleton_class.remove_method(:error)
  end

  test "a failed insert inside a transaction leaves the transaction usable" do
    # Real invalid SQL (raising ActiveRecord::StatementInvalid), so Postgres aborts what it runs in.
    AuditEvent.define_singleton_method(:create!) { |*| connection.execute("SELECT * FROM no_such_table") }
    user = users(:player_one)

    User.transaction do
      assert_nil Audit.record(:sign_in)
      user.update!(name: "Still Writable")
    end

    assert_equal "Still Writable", user.reload.name
  ensure
    AuditEvent.singleton_class.remove_method(:create!)
  end

  test "an unknown action raises outside production" do
    assert_raises(ArgumentError) { Audit.record(:made_up) }
  end
end
