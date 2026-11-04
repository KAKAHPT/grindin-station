# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest # rubocop:disable Metrics/ClassLength
  setup do
    @organizer = event_organizers(:standard_organizer)
  end

  test "the landing renders without signing in, with the hero copy and Anne's seat board" do
    get root_path

    assert_response :success
    assert_select "h1", text: "The tournament software with fair seats."
    assert_includes response.body, "Built for cEDH and multiplayer games, but open to every format."
    assert_select "[data-seat-board] .lp-pod", 4
    assert_select "[data-seat-board] .lp-pod-p.me", count: 4, text: /Anne/
    assert_select "[data-seat-board] .lp-pod-lab em", text: "seat 3"
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

  test "a running tournament stays listed with its state chip and no Register; a finished one is gone" do
    live = upcoming(:swiss, "Live Cup", -2.hours)
    finished = upcoming(:finished, "Done Cup", -3.hours)
    Tournament.where.not(id: [live.id, finished.id]).update_all(start_time: 1.year.from_now) # rubocop:disable Rails/SkipsModelValidations

    get root_path

    assert_select "[data-upcoming-event]:first-child[data-upcoming-event='#{live.slug}']" do
      assert_select ".lp-evr-st", text: /Swiss round/
      assert_select "a[data-register]", count: 0
    end
    assert_select "[data-upcoming-event='#{finished.slug}']", count: 0
  end

  test "the open-for-registration count covers every listed event, not only the six shown" do
    7.times { |index| upcoming(:registration_open, "Open #{index}", (index + 1).minutes) }
    expected = PagesController.listed_tournaments.registration_open.count

    get root_path

    assert_operator expected, :>, 6
    assert_select ".lp-upc-hd span", text: /#{expected} open for registration/
  end

  test "a cover is shown as a resized variant behind its row" do
    event = upcoming(:registration_open, "Cover Cup", 1.minute)
    event.cover.attach(io: Rails.root.join("test/fixtures/files/cover1.jpg").open, filename: "cover1.jpg",
                       content_type: "image/jpeg")

    get root_path

    assert_select "[data-upcoming-event='#{event.slug}'] .lp-evr-ban[style*='/rails/active_storage/representations/']"
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

  test "the Featured section is absent while nothing is featured" do
    upcoming(:registration_open, "Plain Cup", 1.hour)

    get root_path

    assert_select "[data-featured]", count: 0
    assert_select "[data-featured-event]", count: 0
  end

  test "up to three featured tournaments sit above Upcoming as art tickets and leave the Upcoming list" do
    featured = Array.new(4) { |index| upcoming(:registration_open, "Star #{index}", (index + 1).minutes) }
    Tournament.where(id: featured.map(&:id)).update_all(featured: true) # rubocop:disable Rails/SkipsModelValidations
    hidden = upcoming(:draft, "Hidden Star", 1.minute)
    hidden.update_column(:featured, true) # rubocop:disable Rails/SkipsModelValidations
    plain = upcoming(:registration_open, "Plain Cup", 30.seconds)

    get root_path

    assert_select "section.lp-feat[data-featured] + section[data-upcoming]"
    assert_select "[data-featured] h2", text: "Featured"
    assert_select "[data-featured-event]", 3
    assert_select "[data-featured-event]:first-child[data-featured-event='#{featured.first.slug}']" do
      assert_select ".lp-ft-stub b", text: l_day(featured.first)
      assert_select "a[data-register][href=?]", play_event_path(featured.first.slug), text: "Register"
      assert_select ".lp-evr-org", text: /#{@organizer.name}/
    end
    assert_select "[data-featured-event='#{featured.last.slug}']", count: 0
    assert_select "[data-featured-event='#{hidden.slug}']", count: 0
    assert_select "[data-upcoming] [data-upcoming-event='#{plain.slug}']"
    featured.first(3).each { |event| assert_select "[data-upcoming] [data-upcoming-event='#{event.slug}']", count: 0 }
    assert_select "[data-upcoming] [data-upcoming-event='#{featured.last.slug}']"
  end

  test "a sold-out tournament shows the Sold out chip and Join waiting list, on both tickets" do
    event = upcoming(:registration_open, "Full Cup", 1.minute)
    event.update!(maximum_participants: 2, waitlist_enabled: true)
    2.times { |index| enrol(event, index) }
    featured = upcoming(:registration_open, "Full Star", 2.minutes)
    featured.update!(maximum_participants: 1, waitlist_enabled: true, featured: true)
    enrol(featured, 9)

    get root_path

    [["[data-upcoming-event='#{event.slug}']", event], ["[data-featured-event='#{featured.slug}']", featured]]
      .each do |selector, tournament|
        assert_select "#{selector}[data-sold-out]" do
          assert_select "span", text: "Sold out"
          assert_select "span", text: "Registration open", count: 0
          assert_select "a[data-register][href=?]", play_event_path(tournament.slug), text: "Join waiting list"
        end
      end
    assert_select "[data-featured-event='#{featured.slug}'].lp-ft-warn"

    get root_path(locale: "es")
    assert_select "[data-upcoming-event='#{event.slug}'] .lp-evr-st", text: "Agotado"
  end

  test "a sold-out tournament without a waiting list shows Sold out and no Register" do
    event = upcoming(:registration_open, "Shut Cup", 1.minute)
    event.update!(maximum_participants: 1)
    enrol(event, 0)

    get root_path

    assert_select "[data-upcoming-event='#{event.slug}']" do
      assert_select "span", text: "Sold out"
      assert_select "a[data-register]", count: 0
    end
  end

  private

  def l_day(event)
    I18n.l(event.start_time, format: "%d")
  end

  def enrol(event, index)
    user = User.create!(name: "Player #{event.slug} #{index}", password: "password123",
                        email_address: "p#{index}-#{SecureRandom.hex(3)}@example.com")
    event.event_participants.create!(player: user.player, accepted_terms: true)
  end

  def upcoming(state, name, from_now)
    event = Tournament.create!(name: name, event_organizer: @organizer, state: :draft,
                               start_time: from_now.from_now, end_time: (from_now + 1.day).from_now)
    event.update_column(:state, state) # rubocop:disable Rails/SkipsModelValidations
    event
  end
end
