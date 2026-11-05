# frozen_string_literal: true

require "test_helper"

module Admin
  class TrimJobTest < ActiveJob::TestCase
    def audit(age) = AuditEvent.create!(action: "sign_in", created_at: age.ago)
    def error(age) = ErrorEvent.create!(fingerprint: "f", error_class: "E", source: "other", created_at: age.ago)
    def csp(age) = CspReport.create!(violated_directive: "script-src", created_at: age.ago)

    test "rows past their retention are deleted, newer ones stay" do
      old = [audit(13.months), error(91.days), csp(31.days)]
      kept = [audit(11.months), error(89.days), csp(29.days)]

      TrimJob.perform_now

      old.each { |row| assert_not row.class.exists?(row.id), "#{row.class} should be gone" }
      kept.each { |row| assert row.class.exists?(row.id), "#{row.class} should stay" }
    end
  end
end
