# frozen_string_literal: true

require "test_helper"

module Admin
  class EventsControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
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
    test "filters narrow the rows by search, state, tier and format" do
      porto = porto_gold_events.first
      other = events(:standard_tournament)
      other.update_columns(name: "Porto Cup") # rubocop:disable Rails/SkipsModelValidations

      get admin_events_path(q: "porto", state: "finished", tier: "gold", format: "multiplayer")

      assert_response :success
      assert_select "tr[data-event='#{porto.id}']"
      assert_select "tr[data-event='#{other.id}']", count: 0
      assert_select "tr[data-event='#{events(:small_tournament).id}']", count: 0
      assert_select "select[name=tier] option[selected][value=gold]"
    end

    test "search matches the slug and the organizer's name or e-mail; organizer filters by handle" do
      event = events(:finished_tournament)

      get admin_events_path(q: "finished-tourn")
      assert_select "tr[data-event='#{event.id}']"

      get admin_events_path(q: "organizer@example")
      assert_select "tr[data-event='#{event.id}']"

      get admin_events_path(organizer: "organizer-user", q: "Tournament Organizer")
      assert_select "tr[data-event='#{event.id}']"

      get admin_events_path(organizer: "nobody")
      assert_select "tr[data-event]", count: 0
    end

    test "a league state filters leagues only" do
      get admin_events_path(state: "play")

      assert_response :success
      assert_select "tr[data-event='#{events(:small_tournament_swiss).id}']", count: 0
    end

    test "the filters stay in the pagination links and the tier forms" do
      first, second = porto_gold_events
      with_per_page(1) do
        get admin_events_path(q: "porto", tier: "gold")
      end

      assert_select "nav a[href*='page=2'][href*='q=porto'][href*='tier=gold']"
      assert_select "form[action*='filters'][action*='porto']"
      assert_equal 1, css_select("tr[data-event='#{first.id}'], tr[data-event='#{second.id}']").size
    end

    test "setting a tier persists it, audits it, schedules a rebuild and keeps the filters" do
      event = events(:finished_tournament)

      assert_enqueued_with(job: Rankings::RebuildJob) do
        patch tier_admin_event_path(event, filters: { q: "porto", tier: "none" }, page: 2), params: { tier: "gold" }
      end

      assert_redirected_to admin_events_path(q: "porto", tier: "none", page: 2)
      assert_equal "gold", event.reload.tier
      audit = AuditEvent.recent.first
      assert_equal ["tier_changed", users(:admin_user), event.id, { "from" => "none", "to" => "gold" }],
                   [audit.action, audit.actor_user, audit.event_id, audit.data]
    end

    test "an unknown tier is refused and nothing changes" do
      event = events(:finished_tournament)

      assert_no_difference -> { AuditEvent.count } do
        patch tier_admin_event_path(event), params: { tier: "diamond" }
      end

      assert_redirected_to admin_events_path
      assert_equal I18n.t("admin.events.tier_invalid"), flash[:alert]
      assert_equal "none", event.reload.tier
    end

    test "a non-admin cannot set a tier" do
      delete session_path
      post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                              password: "password123" } }
      event = events(:finished_tournament)

      patch tier_admin_event_path(event), params: { tier: "gold" }

      assert_response :not_found
      assert_equal "none", event.reload.tier
    end

    private

    # Two finished, gold, multiplayer events named Porto.
    def porto_gold_events
      [events(:finished_tournament), events(:boundary_five_tournament)].each_with_index.map do |event, i|
        event.update_columns(name: "Porto Open #{i}", tier: "gold", state: 5) # rubocop:disable Rails/SkipsModelValidations
        event
      end
    end

    def with_per_page(count)
      original = EventsController::PER_PAGE
      EventsController.send(:remove_const, :PER_PAGE)
      EventsController.const_set(:PER_PAGE, count)
      yield
    ensure
      EventsController.send(:remove_const, :PER_PAGE)
      EventsController.const_set(:PER_PAGE, original)
    end
  end
end
