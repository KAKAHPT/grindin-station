# frozen_string_literal: true

require "test_helper"

module Organizer
  # A circuit's banner: uploaded from the organizer's circuit form, shown behind its public card and page header.
  class CircuitBannerTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
      @circuit = Circuit.create!(name: "Liga Norte", event_organizer: event_organizers(:standard_organizer))
    end

    test "the organizer uploads a banner and the public pages show it" do
      get edit_organizer_circuit_path(@circuit)
      assert_select "form[enctype='multipart/form-data'] input[type=file][name='circuit[banner]']"

      patch organizer_circuit_path(@circuit),
            params: { circuit: { banner: fixture_file_upload("cover1.jpg", "image/jpeg") } }
      assert_redirected_to organizer_circuit_path(@circuit)
      assert @circuit.reload.banner.attached?

      get circuits_path
      assert_select "a[data-circuit='#{@circuit.id}'][data-circuit-banner][style*='background-image']"
      get circuit_path(@circuit)
      assert_select "[data-circuit-banner]"
    end

    test "a banner of the wrong type is refused" do
      patch organizer_circuit_path(@circuit),
            params: { circuit: { banner: fixture_file_upload("not-an-image.txt", "text/plain") } }
      assert_response :unprocessable_entity
      assert_not @circuit.reload.banner.attached?
    end
  end
end
