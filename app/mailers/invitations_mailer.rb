# frozen_string_literal: true

# Sent when an organizer invites an account to an invitation-only event.
class InvitationsMailer < ApplicationMailer
  def invited(invitation)
    @user = invitation.user
    @event = invitation.event
    mail subject: t("invitations_mailer.invited.subject", event: @event.name), to: @user.email_address
  end
end
