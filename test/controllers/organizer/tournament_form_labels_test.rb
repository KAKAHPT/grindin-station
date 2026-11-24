# frozen_string_literal: true

require "test_helper"

module Organizer
  # The tournament form (New tournament and the Settings tab) labels its fields from activerecord.attributes.event
  # and its submit button from activerecord.models.tournament; without a key there Rails shows the English
  # humanized name ("Start time", "Criar Tournament") in every language.
  class TournamentFormLabelsTest < ActionDispatch::IntegrationTest
    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
    end

    %i[pt es].each do |locale|
      test "no label of the new tournament form falls back to the English attribute name in #{locale}" do
        get new_organizer_tournament_path(locale: locale)

        assert_response :success
        assert_empty untranslated_labels
        assert_select "form button", text: /Tournament/, count: 0
        assert_select "form [placeholder*='1st'], form [placeholder*='First round']", count: 0
      end

      test "no label of the tournament settings falls back to the English attribute name in #{locale}" do
        tournament = TournamentBuilder.build(players: 8, organizer: event_organizers(:standard_organizer),
                                             state: :registration_open)

        get edit_organizer_tournament_path(tournament, locale: locale)

        assert_response :success
        assert_empty untranslated_labels
        assert_select "form button", text: /Tournament/, count: 0
      end
    end

    private

    # The attributes whose label reads exactly as Rails' fallback, e.g. { "start_time" => "Start time" }.
    def untranslated_labels
      labels =
        css_select("form label[for^='tournament_']").to_h do |label|
          [label["for"].delete_prefix("tournament_"), (label.at("span") || label).text.strip]
        end
      assert_includes labels.keys, "start_time", "the form's labels were not found"

      labels.select { |attribute, text| text == attribute.humanize }
    end
  end
end
