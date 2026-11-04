# frozen_string_literal: true

# Writes the audit log. Never blocks the audited action: a failed insert is logged and answers nil.
# An unknown action is a programming error, so it raises outside production.
module Audit
  def self.record(action, actor: Current.user, subject: nil, event: nil, **data)
    AuditEvent.create!(action: action.to_s, actor_user: actor, subject: subject, event: event,
                       ip: Current.ip_address, request_id: Current.request_id, data: data)
  rescue ActiveRecord::RecordInvalid => e
    raise ArgumentError, e.message if e.record.errors.include?(:action) && !Rails.env.production?

    failed(action, e)
  rescue StandardError => e
    failed(action, e)
  end

  def self.failed(action, error)
    Rails.logger.error("Audit.record #{action} failed: #{error.class}: #{error.message}")
    nil
  end
  private_class_method :failed
end
