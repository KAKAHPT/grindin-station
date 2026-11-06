# frozen_string_literal: true

require "test_helper"

module Admin
  class CircuitsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = users(:organizer_user)
      @admin.update_columns(admin: true) # rubocop:disable Rails/SkipsModelValidations
      post session_path, params: { session: { email_address: @admin.email_address, password: "password123" } }
      @circuit = Circuit.create!(name: "ECL 2026", event_organizer: event_organizers(:standard_organizer))
    end

    test "the list has a Featured toggle; a featured circuit comes first on /circuits and shows on the landing" do
      get admin_circuits_path
      assert_response :success
      assert_select "[data-admin-circuits] tr[data-circuit='#{@circuit.id}'] button[aria-pressed=false]",
                    text: "Not featured"

      patch featured_admin_circuit_path(@circuit)
      assert_redirected_to admin_circuits_path
      assert @circuit.reload.featured
      assert_equal "featured_changed", AuditEvent.recent.first.action

      get circuits_path
      assert_select "a[data-circuit]:first-of-type[data-circuit='#{@circuit.id}']"
      assert_select "a[data-circuit='#{@circuit.id}']", text: /Featured/

      get root_path
      assert_select "[data-featured-circuits] a[data-featured-circuit='#{@circuit.id}']", text: /ECL 2026/
    end

    test "non-admins get a 404" do
      @admin.update_columns(admin: false) # rubocop:disable Rails/SkipsModelValidations
      get admin_circuits_path
      assert_response :not_found
    end
  end
end
