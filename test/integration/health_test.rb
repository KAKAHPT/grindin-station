# frozen_string_literal: true

require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "the kamal-proxy health check answers 200 without a session" do
    get "/up"
    assert_response :success
  end
end
