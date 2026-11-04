# frozen_string_literal: true

require "test_helper"

class WaitlistSignupsControllerTest < ActionDispatch::IntegrationTest
  include RateLimitStore

  test "a waiting-list signup is stored and answered in place" do
    assert_difference -> { WaitlistSignup.count }, 1 do
      post waitlist_signups_path, params: { waitlist_signup: { name: "Ana", email: "Ana@Example.com " } },
                                  as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, %(target="waitlist")
    assert_includes response.body, "You&#39;re on the list"
    assert_equal "ana@example.com", WaitlistSignup.last.email
  end

  test "a known e-mail gets the same answer and no second row" do
    WaitlistSignup.create!(name: "Ana", email: "ana@example.com")

    assert_no_difference -> { WaitlistSignup.count } do
      post waitlist_signups_path, params: { waitlist_signup: { name: "Other", email: "ANA@example.com" } },
                                  as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, "You&#39;re on the list"
  end

  test "an invalid e-mail is refused in place" do
    assert_no_difference -> { WaitlistSignup.count } do
      post waitlist_signups_path, params: { waitlist_signup: { name: "Ana", email: "not-an-email" } },
                                  as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_includes response.body, "Check your name and e-mail."
  end

  test "without Turbo the signup redirects back to the landing with a notice" do
    post waitlist_signups_path, params: { waitlist_signup: { name: "Ana", email: "ana@example.com" } }

    assert_redirected_to root_path(anchor: "waitlist")
    assert_equal "You're on the list", flash[:notice]
  end

  test "the waiting list allows five signups per address in ten minutes" do
    with_memory_rate_limit_store do
      5.times do |index|
        post waitlist_signups_path, params: { waitlist_signup: { name: "N#{index}", email: "n#{index}@example.com" } },
                                    as: :turbo_stream
        assert_response :success
      end

      post waitlist_signups_path, params: { waitlist_signup: { name: "N", email: "n@example.com" } },
                                  as: :turbo_stream
      assert_response :too_many_requests
      assert_includes response.body, "Too many tries."

      post waitlist_signups_path, params: { waitlist_signup: { name: "N", email: "n@example.com" } }
      assert_redirected_to root_path(anchor: "waitlist")
      assert_equal "Too many tries. Try again in a few minutes.", flash[:alert]
    end
    assert_equal 5, WaitlistSignup.count
  end
end
