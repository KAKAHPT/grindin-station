# frozen_string_literal: true

require "test_helper"

# Every worker drives its own headless Chrome. One per processor starves them (clicks race the page and tests fail
# at random, on a laptop and on the CI runner alike); two are stable and no slower. PARALLEL_WORKERS overrides.
ActiveSupport::TestCase.parallelize(workers: 2)

# chromedriver 156 reports an element replaced by a Turbo render as UnknownError ("Node with given id does not
# belong to the document"), not StaleElementReferenceError: retry only those; any other UnknownError raises at once.
module RetryDetachedNodes
  DETACHED = /does not belong to the document|stale|detached|not attached/i

  def catch_error?(error, errors = nil)
    return true if super
    return false unless error.is_a?(Selenium::WebDriver::Error::UnknownError) && DETACHED.match?(error.message)

    errors.nil? || errors.include?(Selenium::WebDriver::Error::StaleElementReferenceError)
  end
end
Capybara::Node::Base.prepend(RetryDetachedNodes)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Chrome's password manager flags the fixtures' "password123" as leaked and its dialog swallows every
  # click after signing in, so it is switched off.
  driven_by :selenium, using: :headless_chrome, screen_size: [1280, 960] do |options|
    options.add_preference("credentials_enable_service", false)
    options.add_preference("profile.password_manager_enabled", false)
    options.add_preference("profile.password_manager_leak_detection", false)
    options.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding")
    options.add_option("goog:loggingPrefs", { browser: "ALL" }) # console messages, read by the CSP test
  end

  # Phone emulation stays on the browser between tests, so every session that used it is put back.
  teardown do
    (@phone_sessions || []).uniq.each do |name|
      Capybara.using_session(name) { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }
    end
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

  # Player pages are built for phones; organizer flows keep the default desktop window. Headless Chrome will not
  # shrink the window below 500 px, so the phone is emulated (CDP device metrics) for the current session.
  def use_phone_viewport(width: 390, height: 844)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: width, height: height, deviceScaleFactor: 2, mobile: true)
    (@phone_sessions ||= []) << Capybara.session_name
    assert_equal width, page.evaluate_script("screen.width")
  end
end
