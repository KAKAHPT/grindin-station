# frozen_string_literal: true

require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  test "the action must be a known one" do
    assert_predicate AuditEvent.new(action: "sign_in"), :valid?
    assert_not AuditEvent.new(action: "made_up").valid?
  end

  test "every action of the spec, the rake task and later milestones is known" do
    expected = %w[sign_in sign_in_failed sign_out sign_up oauth_sign_in oauth_failed password_reset_requested
                  password_reset password_changed email_changed account_deleted identity_linked identity_unlinked
                  staff_added staff_removed result_corrected round_undone round_closed participant_dropped
                  event_state_changed infraction_added infraction_removed featured_changed rate_limited
                  admin_granted admin_revoked error_resolved data_exported tier_changed
                  organizer_approved organizer_declined organizer_revoked]
    assert_equal expected.sort, AuditEvent::ACTIONS.sort
  end

  test "recent is newest first; for_action and between filter" do
    old = AuditEvent.create!(action: "sign_in", created_at: 3.days.ago)
    fresh = AuditEvent.create!(action: "sign_out", created_at: 1.hour.ago)

    assert_equal [fresh, old], AuditEvent.recent.to_a
    assert_equal [old], AuditEvent.for_action("sign_in").to_a
    assert_equal [fresh], AuditEvent.between(1.day.ago, Time.current).to_a
  end
end
