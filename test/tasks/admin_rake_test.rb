# frozen_string_literal: true

require "test_helper"
require "rake"

class AdminRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("grindin:admin")
    %w[grindin:admin grindin:admin:revoke].each { |name| Rake::Task[name].reenable }
  end

  test "grindin:admin grants and revoke removes the flag" do
    user = users(:player_one)

    assert_difference -> { AuditEvent.where(action: "admin_granted").count }, 1 do
      Rake::Task["grindin:admin"].invoke(user.email_address)
    end
    assert_predicate user.reload, :admin?

    assert_difference -> { AuditEvent.where(action: "admin_revoked").count }, 1 do
      Rake::Task["grindin:admin:revoke"].invoke(user.email_address)
    end
    assert_not user.reload.admin?

    rows = AuditEvent.where(action: %w[admin_granted admin_revoked])
    assert_equal [nil], rows.map(&:actor_user_id).uniq
    assert_equal [user], rows.map(&:subject).uniq
    assert_equal [{ "email" => user.email_address }], rows.map(&:data).uniq
  end

  test "an unknown email aborts" do
    assert_raises(SystemExit) { Rake::Task["grindin:admin"].invoke("nobody@example.com") }
  end
end
