# frozen_string_literal: true

Kaminari.configure do |config|
  # config.default_per_page = 25
  # config.max_per_page = nil
  # config.window = 4
  # config.outer_window = 0
  # config.left = 0
  # config.right = 0
  # config.page_method_name = :page
  # config.param_name = :page
  # config.max_pages = nil
  # The public standings open on the viewer's own page when no page is asked for, so "Previous" back to the first
  # page has to say page=1.
  config.params_on_first_page = true
end
