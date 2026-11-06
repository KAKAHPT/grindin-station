# frozen_string_literal: true

require "test_helper"

module Organizer
  # Organizer mode → About: description, location, links and banner, shown on the public organizer page.
  class AboutControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:organizer_user)
      post session_path, params: { session: { email_address: @user.email_address, password: "password123" } }
    end

    test "the organizer index links to About, the form saves, and the public page shows it" do # rubocop:disable Metrics/BlockLength
      get organizer_root_path
      assert_select "a[data-organizer-about][href=?]", edit_organizer_about_path, text: "About"

      get edit_organizer_about_path
      assert_response :success
      assert_select "form[action=?][enctype='multipart/form-data']", organizer_about_path
      assert_select "input[name='event_organizer[links][discord]']"

      patch organizer_about_path, params: {
        event_organizer: { description: "cEDH in Lisbon since 2022.\nMonthly leagues.", location: "Lisboa, Portugal",
                           links: { website: "https://cedhpt.com", discord: "https://discord.gg/cedhpt", x: "" } },
        user: { banner: fixture_file_upload("cover1.jpg", "image/jpeg") }
      }
      assert_redirected_to edit_organizer_about_path
      organizer = @user.reload.event_organizer
      assert_equal "Lisboa, Portugal", organizer.location
      assert_equal({ "website" => "https://cedhpt.com", "discord" => "https://discord.gg/cedhpt" }, organizer.links)
      assert @user.banner.attached?

      get organizer_profile_path(@user.handle)
      assert_select "[data-organizer-header][data-organizer-banner]"
      assert_select "[data-organizer-location]", text: /Lisboa, Portugal/
      assert_select "[data-organizer-description]", text: /cEDH in Lisbon since 2022/
      assert_select "[data-organizer-links] a[data-organizer-link=website][href='https://cedhpt.com']", text: "Website"
      assert_select "[data-organizer-links] a[data-organizer-link=discord]", text: "Discord"
      assert_select "[data-organizer-links] a[data-organizer-link=x]", count: 0
      assert_select "[data-upcoming-event].lp-evr-lg", count: 0

      circuit = Circuit.create!(name: "Liga Lisboa", event_organizer: organizer)
      get organizer_profile_path(@user.handle)
      assert_select "[data-organizer-circuits] a[data-circuit='#{circuit.id}']", text: /Liga Lisboa/
    end

    test "a link that is not a full URL is refused" do
      patch organizer_about_path, params: { event_organizer: { links: { instagram: "cedhpt" } } }
      assert_response :unprocessable_entity
      assert_includes response.body, "Instagram must be a full address"
      assert_equal({}, @user.reload.event_organizer.links)
    end

    test "a player without an organizer is sent away" do
      player = users(:player_one)
      player.update!(password: "password123")
      post session_path, params: { session: { email_address: player.email_address, password: "password123" } }
      get edit_organizer_about_path
      assert_response :redirect
      assert_not_equal 200, response.status
    end
  end
end
