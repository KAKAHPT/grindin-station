# frozen_string_literal: true

require "test_helper"

module Admin
  class OrganizersControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
    setup do
      @with_account = WaitlistSignup.create!(name: "Player One", email: users(:player_one).email_address)
      @without_account = WaitlistSignup.create!(name: "Nobody Yet", email: "nobody@example.com")
      sign_in users(:admin_user)
    end

    test "pending signups show name, e-mail, date and whether an account exists" do
      get admin_organizers_path

      assert_response :success
      assert_select "tr[data-signup='#{@with_account.id}']", text: /Player One.*#{Regexp.escape(@with_account.email)}/m
      assert_select "tr[data-signup='#{@with_account.id}'] button", text: I18n.t("admin.organizers.approve")
      assert_select "tr[data-signup='#{@without_account.id}']", text: /#{I18n.t('admin.organizers.no_account')}/
      assert_select "tr[data-signup='#{@without_account.id}'] button", text: I18n.t("admin.organizers.approve"),
                                                                       count: 0
      assert_select "tr[data-signup='#{@without_account.id}'] button", text: I18n.t("admin.organizers.decline")
    end

    test "approving a signup with an account creates the organizer, stamps, audits and e-mails" do
      user = users(:player_one)

      assert_emails 1 do
        assert_difference -> { EventOrganizer.count }, 1 do
          patch approve_admin_organizer_path(@with_account)
        end
      end

      assert_redirected_to admin_organizers_path
      @with_account.reload
      assert_not_nil @with_account.approved_at
      assert_equal users(:admin_user), @with_account.approved_by
      assert_predicate user.reload.event_organizer, :present?
      audit = AuditEvent.recent.first
      assert_equal ["organizer_approved", users(:admin_user), user], [audit.action, audit.actor_user, audit.subject]
      mail = ActionMailer::Base.deliveries.last
      assert_equal [user.email_address], mail.to
      assert_includes mail.text_part.body.to_s, "/organizer"

      get admin_organizers_path(filter: "approved")

      assert_select "tr[data-signup='#{@with_account.id}']"
      get admin_organizers_path

      assert_select "tr[data-signup='#{@with_account.id}']", count: 0
    end

    test "approving someone who already organises keeps the one organizer" do
      signup = WaitlistSignup.create!(name: "Org", email: users(:organizer_user).email_address)

      assert_no_difference -> { EventOrganizer.count } do
        patch approve_admin_organizer_path(signup)
      end

      assert_not_nil signup.reload.approved_at
    end

    test "a signup without an account cannot be approved" do
      assert_no_emails do
        assert_no_difference -> { EventOrganizer.count } do
          patch approve_admin_organizer_path(@without_account)
        end
      end

      assert_redirected_to admin_organizers_path
      assert_equal I18n.t("admin.organizers.no_account_alert"), flash[:alert]
      assert_nil @without_account.reload.approved_at
    end

    test "declining stamps declined_at, audits and sends nothing" do
      assert_no_emails do
        patch decline_admin_organizer_path(@without_account)
      end

      assert_redirected_to admin_organizers_path
      assert_not_nil @without_account.reload.declined_at
      assert_equal ["organizer_declined", @without_account],
                   [AuditEvent.recent.first.action, AuditEvent.recent.first.subject]
      get admin_organizers_path(filter: "declined")

      assert_select "tr[data-signup='#{@without_account.id}']"
    end

    test "an approved signup cannot be declined" do
      @with_account.update!(approved_at: Time.current)

      patch decline_admin_organizer_path(@with_account)

      assert_nil @with_account.reload.declined_at
    end

    test "the organizers list shows name, e-mail and events count" do
      organizer = event_organizers(:standard_organizer)

      get admin_organizers_path

      assert_select "tr[data-organizer='#{organizer.id}']",
                    text: /#{Regexp.escape(organizer.user.email_address)}.*#{organizer.events.count}/m
    end

    test "revoke is refused for an organizer with events" do
      organizer = event_organizers(:standard_organizer)
      assert_predicate organizer.events, :exists?

      assert_no_difference -> { EventOrganizer.count } do
        patch admin_revoke_organizer_path(organizer)
      end

      assert_redirected_to admin_organizers_path
      assert_equal I18n.t("admin.organizers.revoke_refused"), flash[:alert]
    end

    test "revoke is refused for an organizer with a circuit and no events" do
      organizer = EventOrganizer.create!(user: users(:player_two))
      Circuit.create!(name: "Lonely Circuit", event_organizer: organizer)

      get admin_organizers_path

      assert_select "tr[data-organizer='#{organizer.id}'] button", count: 0
      assert_no_difference -> { AuditEvent.count } do
        patch admin_revoke_organizer_path(organizer)
      end

      assert_redirected_to admin_organizers_path
      assert_equal I18n.t("admin.organizers.revoke_refused"), flash[:alert]
      assert EventOrganizer.exists?(organizer.id)
    end

    test "revoke destroys an organizer without events, audits it, and moves their signup out of Approved" do
      user = users(:player_two)
      organizer = EventOrganizer.create!(user: user)
      signup = WaitlistSignup.create!(name: user.name, email: user.email_address, approved_at: 1.day.ago)

      patch admin_revoke_organizer_path(organizer)

      assert_redirected_to admin_organizers_path
      assert_nil EventOrganizer.find_by(id: organizer.id)
      signup.reload
      assert_nil signup.approved_at
      assert_not_nil signup.declined_at
      audit = AuditEvent.recent.first
      assert_equal ["organizer_revoked", user], [audit.action, audit.subject]
    end

    test "the search narrows both lists by name or e-mail" do
      organizer = event_organizers(:standard_organizer)

      get admin_organizers_path(q: "nobody")

      assert_select "tr[data-signup='#{@without_account.id}']"
      assert_select "tr[data-signup='#{@with_account.id}']", count: 0
      assert_select "tr[data-organizer='#{organizer.id}']", count: 0
      assert_select "input[name=q][value=nobody]"

      get admin_organizers_path(q: "Tournament Org")

      assert_select "tr[data-organizer='#{organizer.id}']"
      assert_select "tr[data-signup]", count: 0
    end

    test "an unknown filter falls back to pending; array params are ignored" do
      get admin_organizers_path(filter: "bogus", q: ["x"])

      assert_response :success
      assert_select "tr[data-signup='#{@with_account.id}']"
    end

    test "the index loads the signups' accounts without N+1" do
      WaitlistSignup.create!(name: "Two", email: users(:player_two).email_address)
      EventOrganizer.create!(user: users(:player_three))

      Prosopite.scan
      get admin_organizers_path
      Prosopite.finish

      assert_response :success
    end

    test "non-admins get 404" do
      sign_in users(:player_one)

      get admin_organizers_path
      assert_response :not_found

      patch approve_admin_organizer_path(@with_account)
      assert_response :not_found
      assert_nil @with_account.reload.approved_at
    end

    private

    def sign_in(user)
      post session_path, params: { session: { email_address: user.email_address, password: "password123" } }
    end
  end
end
