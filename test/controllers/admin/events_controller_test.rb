# frozen_string_literal: true

require "test_helper"

module Admin
  class EventsControllerTest < ActionDispatch::IntegrationTest
    setup do
      post session_path, params: { session: { email_address: users(:admin_user).email_address,
                                              password: "password123" } }
    end

    test "lists tournaments and leagues with organizer, state and players" do
      event = events(:standard_tournament)

      get admin_events_path

      assert_response :success
      assert_select "tr[data-event='#{event.id}']", text: /#{Regexp.escape(event.name)}/
      assert_select "tr[data-event='#{event.id}']", text: /#{Regexp.escape(event.event_organizer.user.email_address)}/
    end

    test "the featured toggle flips featured and audits it" do
      event = events(:standard_tournament)
      featured = event.featured

      patch featured_admin_event_path(event)

      assert_redirected_to admin_events_path
      assert_equal !featured, event.reload.featured
      audit = AuditEvent.recent.first
      assert_equal ["featured_changed", users(:admin_user), event.id, { "featured" => !featured }],
                   [audit.action, audit.actor_user, audit.event_id, audit.data]

      patch featured_admin_event_path(event)

      assert_equal featured, event.reload.featured
    end

    test "an event that fails validation can still be toggled" do
      event = events(:standard_tournament)
      event.update_column(:top_cut_size, 999) # rubocop:disable Rails/SkipsModelValidations
      featured = event.featured

      patch featured_admin_event_path(event)

      assert_redirected_to admin_events_path
      assert_equal !featured, event.reload.featured
    end
  end
end
