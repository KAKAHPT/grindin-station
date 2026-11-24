# frozen_string_literal: true

require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  test "the sender is MAIL_FROM when it is set" do
    with_mail_from("grindin@cedhpt.com") do
      assert_equal ["grindin@cedhpt.com"], reset_mail.from
    end
  end

  # Kamal passes an unset secret as an empty string.
  test "an empty MAIL_FROM falls back to noreply at the site's domain" do
    with_mail_from("") do
      assert_equal ["noreply@grindin.test"], reset_mail.from
    end
  end

  private

  def reset_mail = PasswordsMailer.reset(User.first)

  def with_mail_from(value)
    before = ENV.fetch("MAIL_FROM", nil)
    ENV["MAIL_FROM"] = value
    yield
  ensure
    ENV["MAIL_FROM"] = before
  end
end
