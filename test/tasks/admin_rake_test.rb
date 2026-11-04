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

    Rake::Task["grindin:admin"].invoke(user.email_address)
    assert_predicate user.reload, :admin?

    Rake::Task["grindin:admin:revoke"].invoke(user.email_address)
    assert_not user.reload.admin?
  end

  test "an unknown email aborts" do
    assert_raises(SystemExit) { Rake::Task["grindin:admin"].invoke("nobody@example.com") }
  end
end
