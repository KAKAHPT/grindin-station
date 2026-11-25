# frozen_string_literal: true

require "test_helper"

module Admin
  class AccountsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    include ActionMailer::TestHelper

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

    test "resend sends the confirmation e-mail to an unconfirmed account only" do
      sign_in_admin
      pending = unconfirmed

      assert_enqueued_emails 1 do
        post resend_confirmation_admin_account_path(pending)
      end
      assert_redirected_to admin_accounts_path
      assert_equal "confirmation_resent", AuditEvent.recent.first.action

      assert_no_enqueued_emails { post resend_confirmation_admin_account_path(users(:player_one)) }
      assert_equal "That e-mail is already confirmed.", flash[:alert]
    end

    test "block signs the account out and refuses its sign-in until it is unblocked" do
      player = users(:player_one)
      session = player.sessions.create!(user_agent: "t", ip_address: "127.0.0.1")
      sign_in_admin

      patch block_admin_account_path(player)

      assert_predicate player.reload, :blocked?
      assert_not Session.exists?(session.id)
      assert_equal "account_blocked", AuditEvent.recent.first.action
      get admin_accounts_path
      assert_select "tr[data-account='#{player.id}'] [data-blocked]"

      delete session_path
      sign_in(player)
      assert_redirected_to new_session_path
      assert_match(/blocked/, flash[:alert])
      get account_path
      assert_redirected_to new_session_path

      sign_in_admin
      patch unblock_admin_account_path(player)
      assert_not_predicate player.reload, :blocked?
      delete session_path
      sign_in(player)
      assert_redirected_to root_path
    end

    test "a session that is still open ends once its account is blocked" do
      player = users(:player_one)
      sign_in(player)
      get account_path
      assert_response :success

      player.update_column(:blocked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      get account_path
      assert_redirected_to new_session_path
    end

    test "delete anonymises the account and audits it" do
      sign_in_admin
      player = users(:player_one)
      email = player.email_address

      delete admin_account_path(player)

      assert_redirected_to admin_accounts_path
      assert_predicate player.reload, :anonymized?
      assert_not_equal email, player.email_address
      audit = AuditEvent.recent.first
      assert_equal ["account_deleted_by_admin", { "email" => email }], [audit.action, audit.data]
    end

    test "an admin can be neither blocked nor deleted, and gets no such buttons" do
      sign_in_admin
      admin = users(:admin_user)

      patch block_admin_account_path(admin)
      assert_not_predicate admin.reload, :blocked?
      delete admin_account_path(admin)
      assert_not_predicate admin.reload, :anonymized?

      get admin_accounts_path
      assert_select "tr[data-account='#{admin.id}'] form", 0
      assert_select "tr[data-account='#{users(:player_one).id}'] form[action=?]", admin_account_path(users(:player_one))
    end

    test "the actions answer 404 to someone who is not an admin" do
      sign_in(users(:player_two))
      player = users(:player_one)

      patch block_admin_account_path(player)
      assert_response :not_found
      delete admin_account_path(player)
      assert_response :not_found
      post resend_confirmation_admin_account_path(player)
      assert_response :not_found
      assert_not_predicate player.reload, :blocked?
    end

    private

    def unconfirmed
      user = User.create!(name: "Not Yet", email_address: "not-yet@example.com", password: "password123")
      user.update_column(:confirmed_at, nil) # rubocop:disable Rails/SkipsModelValidations
      user
    end

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end

    def sign_in_admin = sign_in(users(:admin_user))
  end
end
