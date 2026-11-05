# frozen_string_literal: true

require "test_helper"

module Admin
  class OverviewTest < ActiveSupport::TestCase
    test "sign-ups per week end with this week and count new users" do
      before = Overview.call.people.signups_per_week
      User.create!(name: "New One", email_address: "new-one@example.com", password: "password123")

      after = Overview.call.people
      assert_equal Overview::WEEKS, after.signups_per_week.size
      assert_equal before.last + 1, after.signups_per_week.last
      assert_equal before[0..-2], after.signups_per_week[0..-2]
    end

    test "errors block counts unresolved groups, not rows" do
      2.times { ErrorEvent.create!(fingerprint: "same", error_class: "RuntimeError", source: "job") }
      ErrorEvent.create!(fingerprint: "done", error_class: "RuntimeError", source: "job", resolved_at: Time.current)

      errors = Overview.call.errors
      assert_equal [1, 3], [errors.unresolved, errors.last_day]
    end
  end
end
