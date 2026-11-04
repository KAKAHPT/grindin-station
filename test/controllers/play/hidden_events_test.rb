# frozen_string_literal: true

require "test_helper"

module Play
  # A draft or canceled event has no public pages: only its staff can open them.
  class HiddenEventsTest < ActionDispatch::IntegrationTest
    setup do
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer))
      @tournament.rounds.create!(type: SwissRound, number: 1).update!(published: true)
    end

    test "draft and canceled events are not found for visitors but open for staff" do
      %i[draft canceled].each do |state|
        @tournament.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
        [play_event_path(@tournament.slug), play_pairings_path(@tournament.slug),
         play_standings_path(@tournament.slug), play_timer_path(@tournament.slug)].each do |path|
          get path
          assert_response :not_found, "#{state} #{path}"
        end
      end

      post session_path, params: { session: { email_address: users(:organizer_user).email_address,
                                              password: "password123" } }
      get play_pairings_path(@tournament.slug)
      assert_response :success
      get play_timer_path(@tournament.slug)
      assert_response :success
    end
  end
end
