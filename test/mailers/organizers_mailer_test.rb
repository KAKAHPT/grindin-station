# frozen_string_literal: true

require "test_helper"

class OrganizersMailerTest < ActionMailer::TestCase
  test "approved tells the user they can organise, with a link to /organizer" do
    user = users(:player_one)

    mail = OrganizersMailer.approved(user)

    assert_equal [user.email_address], mail.to
    assert_equal I18n.t("organizers_mailer.approved.subject"), mail.subject
    assert_includes mail.html_part.body.to_s, "http://example.com/organizer"
    assert_includes mail.text_part.body.to_s, "http://example.com/organizer"
  end
end
