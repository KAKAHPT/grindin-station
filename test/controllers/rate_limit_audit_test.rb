# frozen_string_literal: true

require "test_helper"

class RateLimitAuditTest < ActionDispatch::IntegrationTest
  include RateLimitStore

  test "a refused request is audited once with controller, action and path; allowed ones are not" do
    with_memory_rate_limit_store do
      assert_no_difference -> { AuditEvent.where(action: "rate_limited").count } do
        5.times { post passwords_path, params: { email_address: "player1@example.com" } }
      end

      assert_difference -> { AuditEvent.where(action: "rate_limited").count }, 1 do
        post passwords_path, params: { email_address: "player1@example.com" }
      end
    end

    row = AuditEvent.where(action: "rate_limited").sole
    assert_equal({ "controller" => "passwords", "action" => "create", "path" => "/passwords" }, row.data)
    assert_nil row.actor_user_id
    assert_predicate row.ip, :present?
  end

  test "the actor is the signed-in user when there is one" do
    user = users(:player_one)
    post session_path, params: { session: { email_address: user.email_address, password: "password123" } }

    with_memory_rate_limit_store do
      6.times { post passwords_path, params: { email_address: "player2@example.com" } }
    end

    assert_equal user.id, AuditEvent.where(action: "rate_limited").sole.actor_user_id
  end
end
