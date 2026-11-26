# frozen_string_literal: true

require "application_system_test_case"

# The events list on a 375 px phone: the filters take the whole row and the Grid · List switch sits under them.
class EventsFiltersPhoneTest < ApplicationSystemTestCase
  test "on a phone the filters fill the row, the view switch drops under them and nothing overflows" do
    use_phone_viewport(width: 375, height: 812)
    visit events_path

    boxes = page.evaluate_script(<<~JS)
      (() => {
        const box = (selector) => document.querySelector(selector).getBoundingClientRect();
        const form = box("[data-filter-bar]"), view = box("[data-view-switch]");
        return { formWidth: form.width, formBottom: form.bottom, viewTop: view.top, page: document.documentElement.clientWidth,
                 overflow: document.documentElement.scrollWidth > window.innerWidth };
      })()
    JS
    assert_operator boxes["formWidth"], :>=, boxes["page"] - 40, "the filters take the row"
    assert_operator boxes["viewTop"], :>=, boxes["formBottom"] - 1, "the view switch sits under the filters"
    assert_not boxes["overflow"]
  end
end
