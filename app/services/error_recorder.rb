# frozen_string_literal: true

# Rails.error subscriber: stores each reported error as an ErrorEvent. Never raises (a failed insert is logged).
class ErrorRecorder
  def report(error, handled:, severity:, context:, source: nil) # rubocop:disable Lint/UnusedMethodArgument
    ErrorEvent.create!(
      fingerprint: ErrorEvent.fingerprint_for(error), error_class: error.class.name, message: error.message,
      backtrace: Array(error.backtrace).first(ErrorEvent::BACKTRACE_LINES).join("\n"),
      request_id: Current.request_id, source: source_for(context, source), **who_and_where(context)
    )
  rescue StandardError => e
    Rails.logger.error("ErrorRecorder failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def who_and_where(context)
    { path: context[:path] || Current.request_path, user_id: context[:user_id] || Current.user&.id }
  end

  def source_for(context, source)
    return "request" if context[:controller] || context[:request]
    return "job" if context[:job]

    ErrorEvent::SOURCES.include?(source) ? source : "other"
  end
end
