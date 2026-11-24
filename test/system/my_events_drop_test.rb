# frozen_string_literal: true

require "application_system_test_case"

# Drop on a /my-events ticket asks first: nothing happens unless the player confirms.
class MyEventsDropTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer), state: :swiss)
    @user = users(:player_one)
    @seat = @tournament.event_participants.first
    @seat.update!(player: @user.player)
  end

  test "Drop asks for confirmation: cancelling keeps the player in, accepting drops them" do
    sign_in_as(@user)
    visit my_events_path
    ticket = "[data-upcoming-event='#{@tournament.slug}']"

    message = dismiss_confirm { within(ticket) { click_button I18n.t("my_events.drop") } }
    assert_equal I18n.t("my_events.drop_confirm"), message
    assert_selector "#{ticket} [data-my-drop]"
    assert_not @seat.reload.dropped?

    accept_confirm { within(ticket) { click_button I18n.t("my_events.drop") } }
    assert_text I18n.t("flash.notice.registration_canceled")
    assert_current_path my_events_path
    assert_selector "#{ticket} [data-my-dropped]"
    assert_predicate @seat.reload, :dropped?
  end
end
