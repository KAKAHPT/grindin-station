# frozen_string_literal: true

# http://localhost:3000/rails/mailers/invitations_mailer/invited
class InvitationsMailerPreview < ActionMailer::Preview
  # The mail reads only the invitation's user and event, so the preview needs no saved invitation.
  def invited
    InvitationsMailer.invited(Struct.new(:user, :event).new(User.first, Tournament.first))
  end
end
