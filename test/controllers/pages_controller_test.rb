# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  include RateLimitStore

  setup do
    @organizer = event_organizers(:standard_organizer)
  end

  test "the landing renders without signing in, with the hero copy and Anne's seat board" do
    get root_path

    assert_response :success
    assert_select "h1", text: "The tournament software with fair seats."
    assert_includes response.body, "Built for multiplayer. Open to every format."
    assert_select "[data-seat-board] .lp-sb-p.me", count: 4, text: "Anne"
    assert_select "h2", text: "Seats are weighted, not drawn"
    assert_select ".lp-why li", 4
    assert_select ".lp-mosaic img", 96
    assert_select "[data-attribution]", text: /Wizards of the Coast/
  end

  test "the landing is translated" do
    get root_path(locale: "pt")

    assert_select "h1", text: "O software de torneios com lugares justos."
  end

  test "upcoming events show Register only while registration is open" do
    open = upcoming(:registration_open, "Soon Open Cup", 1.hour)
    closed = upcoming(:registration_closed, "Soon Closed Cup", 2.hours)

    get root_path

    assert_select "[data-upcoming-event='#{open.slug}']" do
      assert_select "a[href=?]", play_event_path(open.slug), text: "View event"
      assert_select "a[data-register][href=?]", play_event_path(open.slug), text: "Register"
      assert_select ".lp-evr-org", text: /#{@organizer.name}/
    end
    assert_select "[data-upcoming-event='#{closed.slug}']" do
      assert_select "a", text: "View event"
      assert_select "a[data-register]", count: 0
    end
  end

  test "draft, canceled and past events are not listed; soonest first, at most six" do
    draft = upcoming(:draft, "Hidden Draft Cup", 1.minute)
    canceled = upcoming(:canceled, "Hidden Canceled Cup", 1.minute)
    past = upcoming(:registration_open, "Past Cup", -1.hour)
    soonest = upcoming(:registration_open, "Soonest Cup", 5.minutes)

    get root_path

    assert_select "[data-upcoming-event]", 6
    assert_select "[data-upcoming-event]:first-child", text: /Soonest Cup/
    [draft, canceled, past].each { |event| assert_select "[data-upcoming-event='#{event.slug}']", count: 0 }
    assert_select "[data-upcoming-event='#{soonest.slug}']"
  end

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
    end
    assert_equal 5, WaitlistSignup.count
  end

  private

  def upcoming(state, name, from_now)
    event = Tournament.create!(name: name, event_organizer: @organizer, state: :draft,
                               start_time: from_now.from_now, end_time: (from_now + 1.day).from_now)
    event.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
    event
  end
end
