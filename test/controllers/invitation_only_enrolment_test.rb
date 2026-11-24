# frozen_string_literal: true

require "test_helper"

# An event by invitation: only an invited account registers itself.
class InvitationOnlyEnrolmentTest < ActionDispatch::IntegrationTest
  setup do
    @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                          state: :registration_open)
    @tournament.update!(invitation_only: true)
    @user = users(:player_one)
    post session_path, params: { session: { email_address: @user.email_address, password: "password123" } }
  end

  test "without an invitation the page says so and registering is refused" do
    get play_event_path(@tournament.slug)
    assert_select "[data-invitation-only]"
    assert_select "[data-not-invited]", text: I18n.t("invitations.not_invited")

    assert_no_difference -> { @tournament.event_participants.count } do
      post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
    end
    assert_equal I18n.t("invitations.not_invited"), flash[:alert]
  end

  test "with an invitation the form shows and registering works" do
    @tournament.event_invitations.create!(user: @user)
    get play_event_path(@tournament.slug)
    assert_select "[data-invited]"
    assert_select "[data-not-invited]", count: 0

    assert_difference -> { @tournament.event_participants.count }, 1 do
      post tournament_event_participants_path(@tournament), params: { event_participant: { accepted_terms: "1" } }
    end
  end

  test "a visitor is told to sign in if invited" do
    delete session_path
    get play_event_path(@tournament.slug)
    assert_select "[data-not-invited]", text: I18n.t("invitations.sign_in_if_invited")
  end
end
