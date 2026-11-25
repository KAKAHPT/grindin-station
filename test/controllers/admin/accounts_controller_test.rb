# frozen_string_literal: true

require "test_helper"

module Admin
  class AccountsControllerTest < ActionDispatch::IntegrationTest
    test "lists every account with e-mail, role, confirmation and the total" do
      sign_in_admin
      pending = User.create!(name: "Not Yet", email_address: "not-yet@example.com", password: "password123")
      pending.update_column(:confirmed_at, nil) # rubocop:disable Rails/SkipsModelValidations

      get admin_accounts_path

      assert_response :success
      assert_select "[data-accounts-total]", text: User.count.to_s
      assert_select "tr[data-account]", User.count
      assert_select "tr[data-account='#{pending.id}']" do
        assert_select "td", text: "not-yet@example.com"
        assert_select "td[data-confirmed=false]", text: "No"
        assert_select "td", text: "Player"
      end
      assert_select "tr[data-account='#{users(:admin_user).id}'] td", text: /Admin/
    end

    test "q searches the name, e-mail or handle" do
      sign_in_admin
      found = User.create!(name: "Zebra Finch", email_address: "zf@example.com", password: "password123")

      get admin_accounts_path(q: "zebra")

      assert_select "tr[data-account]", 1
      assert_select "tr[data-account='#{found.id}']"
    end

    test "someone who is not an admin gets a 404" do
      get admin_accounts_path
      assert_response :not_found

      post session_path, params: { session: { email_address: users(:player_one).email_address,
                                              password: "password123" } }
      get admin_accounts_path
      assert_response :not_found
    end

    private

    def sign_in_admin
      post session_path, params: { session: { email_address: users(:admin_user).email_address,
                                              password: "password123" } }
    end
  end
end
