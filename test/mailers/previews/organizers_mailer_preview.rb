# frozen_string_literal: true

# http://localhost:3000/rails/mailers/organizers_mailer/approved
class OrganizersMailerPreview < ActionMailer::Preview
  def approved
    OrganizersMailer.approved(User.first)
  end
end
