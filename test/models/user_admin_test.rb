# frozen_string_literal: true

require "test_helper"

class UserAdminTest < ActiveSupport::TestCase
  test "admin defaults to false" do
    assert_not users(:organizer_user).admin?
    assert_predicate users(:admin_user), :admin?
  end
end
