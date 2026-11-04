# frozen_string_literal: true

require "test_helper"

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "anonymous visitors get a 404" do
      get admin_root_path

      assert_response :not_found
    end

    test "a non-admin user gets a 404" do
      sign_in users(:organizer_user)

      get admin_root_path

      assert_response :not_found
    end

    test "an admin sees the dashboard" do
      sign_in users(:admin_user)

      get admin_root_path

      assert_response :success
      assert_select "section.card h2.card-title", text: "Admin"
    end

    test "the request context is recorded in Current" do
      sign_in users(:admin_user)
      seen = nil
      Admin::DashboardController.class_eval do
        alias_method :original_show, :show
        define_method(:show) { seen = [Current.ip_address, Current.request_id] }
      end

      begin
        get admin_root_path, headers: { "X-Request-Id" => "req-123" }
      ensure
        Admin::DashboardController.class_eval do
          alias_method :show, :original_show
          remove_method :original_show
        end
      end

      assert_equal "req-123", seen.last
      assert_predicate seen.first, :present?
    end

    private

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
