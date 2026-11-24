# frozen_string_literal: true

require "test_helper"

module Admin
  class PurgeUnattachedBlobsJobTest < ActiveJob::TestCase
    def blob(age)
      ActiveStorage::Blob.create_and_upload!(io: file_fixture("cover1.jpg").open, filename: "c.jpg",
                                             content_type: "image/jpeg").tap { |b| b.update!(created_at: age.ago) }
    end

    test "unattached blobs older than a day are purged; attached and newer ones stay" do
      old_unattached = blob(2.days)
      new_unattached = blob(1.hour)
      old_attached = blob(2.days)
      users(:player_one).avatar.attach(old_attached)

      perform_enqueued_jobs { PurgeUnattachedBlobsJob.perform_now }

      assert_not ActiveStorage::Blob.exists?(old_unattached.id)
      assert_not old_unattached.service.exist?(old_unattached.key), "the file is deleted from disk"
      assert ActiveStorage::Blob.exists?(new_unattached.id)
      assert ActiveStorage::Blob.exists?(old_attached.id)
      assert old_attached.service.exist?(old_attached.key)
    end
  end
end
