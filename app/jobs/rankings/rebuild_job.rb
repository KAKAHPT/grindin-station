# frozen_string_literal: true

module Rankings
  # Rebuilds the stored rankings (Rankings::Rebuild): nightly, and five minutes after an event finishes or a
  # result is corrected, at most one pending run at a time (schedule!).
  class RebuildJob < ApplicationJob
    PENDING_KEY = "rankings:rebuild:scheduled"
    DELAY = 5.minutes

    # Enqueues a rebuild in five minutes unless one is already pending.
    def self.schedule!
      return unless Rails.cache.write(PENDING_KEY, true, unless_exist: true, expires_in: DELAY)

      set(wait: DELAY).perform_later
    end

    def perform
      Rails.cache.delete(PENDING_KEY)
      Rebuild.call
    end
  end
end
