# frozen_string_literal: true

require "test_helper"

# chromedriver reports a node replaced by a Turbo render as UnknownError ("Node with given id does not belong
# to the document") rather than StaleElementReferenceError; let Capybara retry it like a stale element.
module RetryDetachedNodes
  def invalid_element_errors
    super + [Selenium::WebDriver::Error::UnknownError]
  end
end
Capybara::Selenium::Driver.prepend(RetryDetachedNodes)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Chrome's password manager flags the fixtures' "password123" as leaked and its dialog swallows every
  # click after signing in, so it is switched off.
  driven_by :selenium, using: :headless_chrome, screen_size: [1280, 960] do |options|
    options.add_preference("credentials_enable_service", false)
    options.add_preference("profile.password_manager_enabled", false)
    options.add_preference("profile.password_manager_leak_detection", false)
    options.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding")
  end

  private

  # Waits for the sign-in redirect so the next visit does not race the session cookie.
  def sign_in_as(user, password: "password123")
    visit new_session_path
    fill_in "session_email_address", with: user.email_address
    fill_in "session_password", with: password
    click_button "Sign in"
    assert_text I18n.t("flash.notice.signed_in")
  end

  # Player pages are built for phones; organizer flows keep the default desktop window.
  def use_phone_viewport
    page.driver.browser.manage.window.resize_to(390, 844)
  end
end
