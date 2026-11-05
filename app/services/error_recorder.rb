# frozen_string_literal: true

# Rails.error subscriber: stores each reported error as an ErrorEvent. Never raises (a failed insert is logged).
# The insert joins any open transaction, so an error reported inside one that rolls back leaves no row.
class ErrorRecorder
  MAX_MESSAGE_LENGTH = 4000

  def report(error, handled:, severity:, context:, source: nil) # rubocop:disable Lint/UnusedMethodArgument
    ErrorEvent.create!(
      fingerprint: ErrorEvent.fingerprint_for(error), error_class: error.class.name, **details(error),
      request_id: Current.request_id, source: source_for(context, source), **who_and_where(context)
    )
  rescue StandardError => e
    Rails.logger.error("ErrorRecorder failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def details(error)
    { message: error.message.to_s.first(MAX_MESSAGE_LENGTH),
      backtrace: Array(error.backtrace).first(ErrorEvent::BACKTRACE_LINES).join("\n") }
  end

  def who_and_where(context)
    { path: context[:path] || Current.request_path, user_id: context[:user_id] || Current.user&.id }
  end

  def source_for(context, source)
    return "request" if context[:controller] || context[:request]
    return "job" if context[:job]

    ErrorEvent::SOURCES.include?(source) ? source : "other"
  end
end
