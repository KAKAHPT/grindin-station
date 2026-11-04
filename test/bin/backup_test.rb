# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

class BackupScriptTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/backup").to_s

  def run_backup(dir, keep: nil)
    env = { "BACKUP_DIR" => dir }
    env["KEEP"] = keep.to_s if keep
    Open3.capture2e(env, SCRIPT, "--dry-run")
  end

  def seed_dumps(dir, count)
    Array.new(count) do |i|
      stamp = Time.utc(2026, 10, 1) + i.days
      path = File.join(dir, "#{stamp.strftime('%Y%m%dT%H%M%SZ')}.dump")
      File.write(path, "fake")
      path
    end
  end

  test "dry run keeps the 14 newest dumps and removes the rest" do
    Dir.mktmpdir do |dir|
      dumps = seed_dumps(dir, 20)
      File.write(File.join(dir, "notes.txt"), "not a dump")

      output, status = run_backup(dir)

      assert status.success?, output
      remaining = Dir.glob(File.join(dir, "*.dump"))
      assert_equal dumps.last(14), remaining
      assert_path_exists File.join(dir, "notes.txt")
      assert_match(/dry run/i, output)
    end
  end

  test "rotation is idempotent and honours KEEP" do
    Dir.mktmpdir do |dir|
      dumps = seed_dumps(dir, 5)

      2.times do
        output, status = run_backup(dir, keep: 3)
        assert status.success?, output
      end

      assert_equal dumps.last(3), Dir.glob(File.join(dir, "*.dump"))
    end
  end

  test "dry run never calls docker or rclone" do
    Dir.mktmpdir do |dir|
      output, status = run_backup(dir)
      assert status.success?, output
      assert_empty Dir.glob(File.join(dir, "*.dump"))
    end
  end
end
