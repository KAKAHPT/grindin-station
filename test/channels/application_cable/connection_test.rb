# frozen_string_literal: true

require "test_helper"

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    test "a visitor without a session connects anonymously" do
      connect

      assert_nil connection.current_user
    end

    test "a signed-in user connects as themselves" do
      user = users(:organizer_user)
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      cookies.signed[:session_id] = session.id

      connect

      assert_equal user, connection.current_user
    end

    test "an expired session connects as a visitor" do
      session = users(:organizer_user).sessions.create!(user_agent: "test", created_at: 31.days.ago)
      cookies.signed[:session_id] = session.id

      connect

      assert_nil connection.current_user
    end
  end
end
