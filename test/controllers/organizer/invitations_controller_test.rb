# frozen_string_literal: true

require "test_helper"

module Organizer
  class InvitationsControllerTest < ActionDispatch::IntegrationTest
    include ActionMailer::TestHelper

    setup do
      post session_path,
           params: { session: { email_address: users(:organizer_user).email_address, password: "password123" } }
      @tournament = TournamentBuilder.build(players: 4, organizer: event_organizers(:standard_organizer),
                                            state: :registration_open)
      @tournament.update!(invitation_only: true)
      @guest = users(:player_one)
      @player = @guest.player || Player.create!(user: @guest, name: @guest.name)
    end

    test "the tab shows only on an event by invitation" do
      get organizer_tournament_path(@tournament)
      assert_select "a[href=?]", organizer_tournament_invitations_path(@tournament)

      @tournament.update!(invitation_only: false)
      get organizer_tournament_path(@tournament)
      assert_select "a[href=?]", organizer_tournament_invitations_path(@tournament), count: 0
    end

    test "searching by name finds a registered player to invite" do
      get organizer_tournament_invitations_path(@tournament, q: @guest.name.first(4))
      assert_response :success
      assert_select "[data-result='#{@player.id}']", text: /#{@guest.name}/
    end

    test "inviting sends one e-mail, inviting again sends it again, removing takes it back" do
      assert_enqueued_emails 1 do
        assert_difference -> { @tournament.event_invitations.count }, 1 do
          post organizer_tournament_invitations_path(@tournament), params: { player_id: @player.id }
        end
      end
      invitation = @tournament.event_invitations.last
      assert_equal [@guest, users(:organizer_user)], [invitation.user, invitation.invited_by]

      assert_enqueued_emails 1 do
        assert_no_difference -> { EventInvitation.count } do
          post organizer_tournament_invitations_path(@tournament), params: { player_id: @player.id }
        end
      end

      get organizer_tournament_invitations_path(@tournament)
      assert_select "[data-invitations] tr", text: /#{@guest.name}/

      assert_difference -> { EventInvitation.count }, -1 do
        delete organizer_tournament_invitation_path(@tournament, invitation)
      end
    end

    test "the e-mail links to the event" do
      invitation = @tournament.event_invitations.create!(user: @guest, invited_by: users(:organizer_user))
      mail = InvitationsMailer.invited(invitation)
      assert_equal [@guest.email_address], mail.to
      assert_includes mail.subject, @tournament.name
      assert_includes mail.text_part.body.to_s, play_event_path(@tournament.slug)
    end

    test "a judge cannot open the invitations" do
      delete session_path
      judge = users(:player_two)
      @tournament.event_staff.create!(user: judge, role: "judge")
      post session_path, params: { session: { email_address: judge.email_address, password: "password123" } }
      get organizer_tournament_invitations_path(@tournament)
      assert_not_equal 200, response.status
    end
  end
end
