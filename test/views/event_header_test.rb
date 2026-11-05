# frozen_string_literal: true

require "test_helper"

class EventHeaderTest < ActionView::TestCase
  setup do
    @event = TournamentBuilder.build(players: 2, organizer: event_organizers(:standard_organizer))
  end

  test "without a cover: corner mark, title, eyebrow, line and actions over the ticket's fallback art" do
    render "shared/event_header", event: @event, eyebrow: "Tournament · Draft", title: "Demo Cup",
                                  line: "4 Nov 2026 · Lisboa", actions: tag.a("View public page", href: "#")

    assert_select ".evhead .evhead-corner .gslogo[data-rotating]", count: 1
    assert_select ".evhead-ban[style*=?]", "/assets/landing/c" # the same art the event's ticket shows
    assert_select ".evhead-shade"
    assert_select ".evhead-eyebrow", text: "Tournament · Draft"
    assert_select "h1.evhead-title", text: "Demo Cup"
    assert_select ".evhead-line", text: "4 Nov 2026 · Lisboa"
    assert_select ".evhead-actions a", text: "View public page"
  end

  test "with a cover: the cover blurred behind, title defaults to the event name" do
    @event.cover.attach(io: StringIO.new(Rails.root.join("test/fixtures/files/cover1.jpg").binread),
                        filename: "cover1.jpg", content_type: "image/jpeg")

    render "shared/event_header", event: @event

    assert_select ".evhead-corner .gslogo"
    assert_select ".evhead-ban[style*=?]", "cover1.jpg"
    assert_select ".evhead-ban[style*=?]", "/rails/active_storage/representations/" # resized, as on the tickets
    assert_select "h1.evhead-title", text: @event.name
    assert_select ".evhead-actions", count: 0
  end
end
