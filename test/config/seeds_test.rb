# frozen_string_literal: true

require "test_helper"
require "open3"

class SeedsTest < ActiveSupport::TestCase
  # The seeds create organizers with a known password: they must refuse to run in production.
  test "db/seeds.rb aborts in production before touching the database" do
    script = <<~RUBY
      module Rails
        def self.env = Struct.new(:production?).new(true)
      end
      load #{Rails.root.join('db/seeds.rb').to_s.inspect}
    RUBY
    _out, err, status = Open3.capture3(RbConfig.ruby, "-e", script)

    assert_not status.success?
    assert_includes err, "Seeds are for development only"
  end
end
