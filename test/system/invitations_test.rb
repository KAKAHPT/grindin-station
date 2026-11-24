# frozen_string_literal: true

require "application_system_test_case"

# The organizer turns "Invitation only" on, finds a player by name and invites them.
class InvitationsTest < ApplicationSystemTestCase
  setup do
    @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                          state: :registration_open)
    @tournament.update!(invitation_only: true)
  end

  test "the organizer searches a player by name and invites them" do
    sign_in_as(users(:organizer_user))
    visit organizer_tournament_path(@tournament)
    click_on I18n.t("organizer.shell.tabs.invitations")

    fill_in I18n.t("invitations.search"), with: "Player"
    click_on I18n.t("invitations.find")
    within("[data-invite-search]") { first(:button, I18n.t("invitations.invite")).click }

    assert_selector "[data-invitations] tbody tr", count: 1
    assert_selector "[data-invitations]", text: I18n.t("invitations.waiting")
    page.save_screenshot(ENV["SHOT"]) if ENV["SHOT"]
  end
end
