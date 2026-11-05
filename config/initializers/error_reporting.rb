# frozen_string_literal: true

# Reported errors (unhandled request and job exceptions included) are stored for /admin/errors. Tests subscribe
# the recorder themselves.
Rails.application.config.after_initialize { Rails.error.subscribe(ErrorRecorder.new) } unless Rails.env.test?
