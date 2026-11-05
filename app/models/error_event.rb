# frozen_string_literal: true

# One reported error (written by ErrorRecorder). Occurrences of the same error share a fingerprint.
class ErrorEvent < ApplicationRecord
  SOURCES = %w[request job other].freeze
  BACKTRACE_LINES = 30

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :grouped, lambda {
    group(:fingerprint)
      .select(:fingerprint, "COUNT(*) AS occurrences", "MAX(created_at) AS last_seen_at")
      .order(last_seen_at: :desc)
  }

  def self.fingerprint_for(error)
    frame = Array(error.backtrace).find { |line| line.include?("/app/") }
    Digest::SHA256.hexdigest("#{error.class.name}|#{frame || error.message}")
  end
end
