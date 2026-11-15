# frozen_string_literal: true

module Admin
  # Nightly: purges files no record uses any more (a replaced or failed upload) once they are a day old, so the disk
  # only keeps attached avatars, banners and covers. Newer ones are left alone: an upload may still be attaching.
  class PurgeUnattachedBlobsJob < ApplicationJob
    AGE = 1.day

    def perform
      ActiveStorage::Blob.unattached.where(created_at: ...AGE.ago).find_each(&:purge_later)
    end
  end
end
